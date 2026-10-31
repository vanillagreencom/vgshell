import QtQuick
import QtQuick.Window

// Stands in for Quickshell's PopupWindow under the unit tests: a plain
// window with the anchor members the overlays set and read, typed so a
// grouped assignment such as `anchor.margins.top` resolves. It positions
// nothing; the nested sandbox proves placement.
Window {
    id: window

    component Margins: QtObject {
        property int top: 0
        property int right: 0
        property int bottom: 0
        property int left: 0
    }
    component Box: QtObject {
        property real x: 0
        property real y: 0
        property real width: 0
        property real height: 0
    }
    component Anchor: QtObject {
        property Item item: null
        property QtObject window: null
        property int edges: 0
        property int gravity: 0
        property int adjustment: 0
        property int updates: 0
        readonly property Margins margins: Margins {}
        readonly property Box rect: Box {}
        function updateAnchor() { updates += 1; }
    }

    property bool grabFocus: false
    property bool connected: false
    // Holds this window's items between a hide and the next show, hidden
    // and as large as the window, as Quickshell's content item follows the
    // window's implicit size while no backing window exists
    // (proxywindow.cpp setImplicitWidth and onWidthChanged, 0.3.1).
    readonly property Item holder: Item { visible: false; width: window.width; height: window.height }

    // Quickshell makes the backing window on the first show and then
    // emits windowConnected; this window exists from the start, so it
    // emits the signal on its first show.
    signal windowConnected()
    // Quickshell's PopupWindow deletes its backing window on every hide and
    // takes its content off it, so the content reads hidden until the next
    // show puts it on a new window, before visibleChanged
    // (src/window/popupwindow.cpp deleteOnInvisible, proxywindow.cpp
    // setVisibleDirect and disownWindow, 0.3.1). Qt counts an item taken off
    // its parent as hidden, with all it holds (qmltestrunner, Qt 6.12.0,
    // 2026-10-31).
    onVisibleChanged: {
        if (visible) {
            for (const item of Array.from(holder.children)) item.parent = contentItem;
        } else {
            for (const item of Array.from(contentItem.children)) item.parent = holder;
        }
        if (visible && !connected) {
            connected = true;
            windowConnected();
        }
    }
    property QtObject mask: null
    property int implicitWidth: 0
    property int implicitHeight: 0
    readonly property Anchor anchor: Anchor {}

    width: Math.max(1, implicitWidth)
    height: Math.max(1, implicitHeight)
    // Quickshell 0.3.1 uses a non-grabbing Qt ToolTip, or a grabbing Popup.
    // https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/window/popupwindow.cpp#L56
    flags: (grabFocus ? Qt.Popup : Qt.ToolTip) | Qt.FramelessWindowHint
}
