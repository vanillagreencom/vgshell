import QtQuick
import Quickshell
import qs.Core
import qs.Commons
import qs.Ui

// The anchor's window owns the popup; the compositor adjusts its position
// at screen edges. Every anchored surface takes the focus grab: it is what
// gives the popup keyboard focus under a bar whose layer takes none, and
// what closes it on a click outside. Losing the anchor closes it too.
PopupWindow {
    id: popup

    required property string pluginId
    required property string kind
    required property var request
    readonly property Item anchorItem: request ? request.anchor : null
    readonly property Item returnFocusItem: request && request.returnFocus ? request.returnFocus : null
    readonly property bool returnFocusWasVisual: !!(request && request.returnFocusWasVisual)
    property bool closing: false
    property real motionProgress: 0
    readonly property real cardOpacity: card.opacity
    readonly property real cardTranslateY: cardOffset.y
    signal built(var instance)
    signal dismissed()

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
    grabFocus: true
    visible: anchorItem !== null
    // The room the output leaves, `size.window.gutter` in from each edge: a
    // plugin wider or taller than that is laid out at the room's size, since
    // the plugin fills its card, and the compositor's slide keeps the
    // popup inside the output.
    readonly property var output: request && request.screen ? request.screen : null
    readonly property var room: OverlayState.room(output)
    implicitWidth: slot.instance ? Math.max(1, Math.min(slot.instance.implicitWidth, room.width)) : 1
    // The native height: the room on the anchor's side, taken once at open,
    // and never lowered while the popup shows, so an expand or a collapse
    // sends the compositor no resize. Each resize is an xdg_popup.reposition
    // round trip, during which Qt draws nothing, and a new swapchain
    // (qtbase 6.11 QWaylandXdgSurface::setWindowSize).
    property real keptHeight: 0
    implicitHeight: Math.ceil(Math.max(keptHeight, sized.surface))
    color: "transparent"
    // Input reaches only the drawn card: a press on the room below it lands
    // on what lies under the popup, outside the grab, which dismisses it.
    // The card's resting box, not `item: sized`: Quickshell's Region maps
    // its item through the slide's Translate but rebuilds only on the
    // item's x, y, width or height, so it kept the open motion's first
    // frame and left the card's bottom `motion.flyout.slide` outside
    // (surfaces row, the mask control).
    // Region's box is whole pixels; the card's height is fractional.
    mask: Region { x: sized.x; y: sized.y; width: Math.ceil(sized.width); height: Math.ceil(sized.height) }
    Component.onCompleted: Qt.callLater(() => setMotion(1, false))
    // Quickshell PopupWindow::onClosed sets the wanted visibility false
    // after the compositor closes the xdg_popup, so that path cannot commit
    // a closing frame.
    onVisibleChanged: {
        if (!visible) {
            if (returnFocusWasVisual && returnFocusItem !== null && returnFocusItem.forceActiveFocus !== undefined) {
                const target = returnFocusItem;
                Qt.callLater(() => {
                    target.focus = false;
                    target.forceActiveFocus(Qt.ShortcutFocusReason);
                });
            }
            dismissed();
        }
    }
    onAnchorItemChanged: if (anchorItem === null) requestDismiss()

    function focusInitial() {
        slot.focusInitial();
    }

    function setMotion(target, dismissAfter) {
        flyoutMotion.stop();
        if (Theme.motion.flyout.travel.duration <= 0) {
            motionProgress = target;
            if (dismissAfter) finishDismiss();
            return;
        }
        flyoutMotion.to = target;
        flyoutMotion.dismissAfter = dismissAfter;
        flyoutMotion.duration = Theme.motion.flyout.travel.duration;
        flyoutMotion.easing.type = Theme.motion.flyout.travel.easing;
        flyoutMotion.start();
    }

    // The plugin hears close() when the card has left, not as it starts
    // to: a plugin that clears its content on close() would empty the card
    // during the motion.
    function requestDismiss() {
        if (closing) return;
        closing = true;
        setMotion(0, true);
    }

    function finishDismiss() {
        slot.closeInstance();
        visible = false;
    }

    function closeFromHost() {
        requestDismiss();
    }

    function reopenFromHost() {
        slot.resetCloseState();
        closing = false;
        visible = true;
        setMotion(1, false);
    }

    // The height from the anchor's bottom edge to the output's bottom, less
    // the gutter, for an anchor in a strip pinned to the output's top edge
    // alone, as the bar is: that layer's top is its top margin (Quickshell's
    // PanelWindow), and QsWindow.itemRect places the anchor in it. A popup
    // that tall fits below the anchor, so the compositor neither flips nor
    // slides it. 0 for any other anchor, whose position on the output a
    // client cannot read: a toplevel's under Wayland, or a layer the
    // compositor places below another's exclusive zone, as a summoned panel
    // anchored to every edge sits under the bar (surfaces row: a nested
    // menu from such a panel slid up over its anchor). That popup's height
    // grows with its content and never shrinks while it shows.
    function roomBelow() {
        const win = anchorItem === null ? null : anchorItem.QsWindow.window;
        if (win === null || output === null || win.anchors === undefined || !win.anchors.top || win.anchors.bottom) return 0;
        const rect = win.itemRect(anchorItem);
        return Math.max(1, Math.floor(output.height - win.margins.top - rect.y - rect.height - Theme.size.window.gutter));
    }
    Connections {
        target: sized
        function onSurfaceChanged() { popup.keptHeight = Math.max(popup.keptHeight, sized.surface); }
    }

    // The anchor follows every move of the item or an ancestor. The
    // compositor learns the new anchor on the popup's next frame; the log
    // line is the validation rows' readback until then. A hidden anchor
    // closes the popup through its own close motion.
    readonly property AnchorTracker tracker: AnchorTracker {
        popup: popup
        anchor: popup.anchorItem
        closeOnHide: false
        onFollowed: console.info("summon popup: anchor updated for " + popup.pluginId)
        onAnchorHidden: popup.requestDismiss()
    }

    NumberAnimation {
        id: flyoutMotion
        target: popup
        property: "motionProgress"
        from: popup.motionProgress
        property bool dismissAfter: false
        onStopped: if (dismissAfter && popup.closing && popup.motionProgress === 0) popup.finishDismiss()
    }

    // The card fades as one image. Qt applies an item's opacity to each
    // child on its own, so a plugin's opaque fill over its card's fill let
    // the faded card show through it and stood out lighter mid-motion; a
    // layer draws the subtree at full opacity, then fades that texture
    // (Qt 6 Item, "Layer Opacity vs Item Opacity"). The layer covers the
    // window, not the card, so a glass shadow past the card's edge fades
    // with it. It exists only while the card moves.
    Item {
        id: card
        anchors.fill: parent
        opacity: popup.motionProgress
        layer.enabled: popup.motionProgress < 1
        transform: Translate {
            id: cardOffset
            y: -Theme.motion.flyout.slide * (1 - popup.motionProgress)
        }

        SurfaceHeight {
            id: sized
            room: Math.min(popup.roomBelow(), popup.room.height)
            target: slot.instance ? Math.max(1, Math.min(slot.instance.implicitHeight, sized.room > 0 ? sized.room : popup.room.height)) : 1

            PluginSlot {
                id: slot
                kind: popup.kind
                pluginId: popup.pluginId
                hostKey: popup.kind
                settingsPage: Registry.settingsPageOf(popup.kind, popup.pluginId)
                screen: popup.screen
                closeOnUnload: true
                anchors.fill: parent
                // The slot gives its focus to the key sink below while the card
                // closes, and a reopen takes it back with the focus the plugin
                // had inside it.
                focus: !popup.closing
                Keys.onEscapePressed: popup.requestDismiss()
                onBuilt: instance => {
                    popup.built(instance);
                    slot.focusInitial();
                }
                onBuildFailed: key => popup.requestDismiss()
            }

            // A closing card takes no key: the sink holds the focus and accepts
            // every key. Without it Tab would focus a control in the card, since
            // Qt's tab chain enters any enabled item and the card stays enabled.
            Item {
                focus: popup.closing
                Keys.onPressed: event => event.accepted = true
            }

            // A closing card takes no press or wheel, and stays enabled: every
            // qs.Ui control draws its disabled look from `enabled`. A pointer
            // handler under this area is still offered the press. Hidden, it
            // still makes Qt skip the card's children for a press outside the
            // card: Qt 6.11 QQuickItemPrivate::effectivelyClipsEventHandlingChildren
            // reads a child's accepted buttons, not its visibility, and keeps
            // the last child's answer. Outside the card is outside the mask.
            // keyboard-path: none, as this blocks input and takes no action
            // pointer-cursor-exempt: it covers a closing card, not a control
            MouseArea {
                anchors.fill: parent
                visible: popup.closing
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => wheel.accepted = true
            }
        }
    }
}
