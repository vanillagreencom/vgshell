import QtQuick
import QtQuick.Window
import QtQml.Models

// Keeps a popup window with the item it opened from. The compositor places
// the popup once from its anchor rect and moves it again only when the
// anchor is updated, and a hidden anchor leaves it open. This watches the
// anchor and every ancestor for a move, a resize and a hide: a move
// updates the anchor, and a hide closes the popup. Every overlay and the
// summoned popup host hold one.
QtObject {
    id: tracker

    required property var popup
    required property Item anchor
    // A popup host with its own close closes on `anchorHidden` and sets
    // this false.
    property bool closeOnHide: true
    signal anchorHidden()
    // Each anchor update.
    signal followed()

    // The anchor and every ancestor up to the window's content item.
    readonly property var chain: {
        const out = [];
        for (let item = anchor; item; item = item.parent) out.push(item);
        return out;
    }

    function follow() {
        if (!popup.visible) return;
        popup.anchor.updateAnchor();
        followed();
        moved = true;
        requestFrame();
    }

    // Quickshell sends xdg_popup.reposition during the popup's polish; Qt
    // needs QQuickWindow.update() to commit a frame when only the anchor
    // changed.
    function requestFrame() {
        const window = popup.contentItem ? popup.contentItem.Window.window : null;
        if (window !== null) window.update();
    }

    // A neighbour that sizes in its window's polish pass, as a Row does,
    // moves the anchor during that pass, and Qt 6.11's threaded render loop
    // drops an update any window asks for while one polishes
    // (QSGThreadedRenderLoop::maybeUpdate, m_inPolish), so the popup would
    // not draw, nor reposition, until something else drew it. The anchor's
    // window emits afterAnimating on the GUI thread once its polish ends,
    // in the same frame, where the request stands.
    property bool moved: false
    readonly property Connections polishFlush: Connections {
        target: tracker.anchor ? tracker.anchor.Window.window : null
        enabled: tracker.moved
        function onAfterAnimating() {
            tracker.moved = false;
            tracker.requestFrame();
        }
    }

    function hide() {
        anchorHidden();
        if (closeOnHide) popup.visible = false;
    }

    readonly property Instantiator watchers: Instantiator {
        model: tracker.chain
        delegate: Connections {
            required property var modelData
            target: modelData
            function onXChanged() { tracker.follow(); }
            function onYChanged() { tracker.follow(); }
            function onWidthChanged() { tracker.follow(); }
            function onHeightChanged() { tracker.follow(); }
            function onRotationChanged() { tracker.follow(); }
            function onScaleChanged() { tracker.follow(); }
            function onVisibleChanged() { if (!target.visible) tracker.hide(); }
        }
    }
}
