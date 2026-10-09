import QtQuick
import QtQuick.Window
import QtQml.Models
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
    mask: Region { item: sized }
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

    function requestDismiss() {
        if (closing) return;
        closing = true;
        slot.closeInstance();
        setMotion(0, true);
    }

    function finishDismiss() {
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

    // The anchor is re-read on every move of the item or an ancestor, since
    // a layout can move the item without changing its own x or y. The
    // compositor learns the new anchor on the popup's next frame; the log
    // line is the validation rows' readback until then.
    function followAnchor() {
        console.info("summon popup: anchor updated for " + pluginId);
        anchor.updateAnchor();
        const window = contentItem ? contentItem.Window.window : null;
        // Quickshell sends xdg_popup.reposition during the popup's polish;
        // Qt needs QQuickWindow.update() to commit a frame when only the
        // anchor changed.
        if (window !== null) window.update();
    }
    readonly property var anchorChain: {
        const chain = [];
        for (let item = anchorItem; item; item = item.parent) chain.push(item);
        return chain;
    }
    Instantiator {
        model: popup.anchorChain
        delegate: Connections {
            required property var modelData
            target: modelData
            function onXChanged() { popup.followAnchor(); }
            function onYChanged() { popup.followAnchor(); }
            function onWidthChanged() { popup.followAnchor(); }
            function onHeightChanged() { popup.followAnchor(); }
            function onRotationChanged() { popup.followAnchor(); }
            function onScaleChanged() { popup.followAnchor(); }
            function onVisibleChanged() { if (!target.visible) popup.requestDismiss(); }
        }
    }

    NumberAnimation {
        id: flyoutMotion
        target: popup
        property: "motionProgress"
        from: popup.motionProgress
        property bool dismissAfter: false
        onStopped: if (dismissAfter && popup.closing && popup.motionProgress === 0) popup.finishDismiss()
    }

    SurfaceHeight {
        id: sized
        room: Math.min(popup.roomBelow(), popup.room.height)
        target: slot.instance ? Math.max(1, Math.min(slot.instance.implicitHeight, sized.room > 0 ? sized.room : popup.room.height)) : 1
        opacity: popup.motionProgress
        transform: Translate {
            y: -Theme.motion.flyout.slide * (1 - popup.motionProgress)
        }

        PluginSlot {
            id: slot
            kind: popup.kind
            pluginId: popup.pluginId
            hostKey: popup.kind
            settingsPage: Registry.settingsPageOf(popup.kind, popup.pluginId)
            screen: popup.screen
            closeOnUnload: true
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: popup.requestDismiss()
            onBuilt: instance => {
                popup.built(instance);
                slot.focusInitial();
            }
            onBuildFailed: key => popup.requestDismiss()
        }
    }
}
