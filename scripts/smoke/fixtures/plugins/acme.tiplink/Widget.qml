import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
// A bar widget whose item's tooltip names a page of another plugin, with
// the readers scripts/smoke/rows/bar.sh points, presses and types by.
BarWidget {
    id: root
    implicitWidth: item.implicitWidth
    implicitHeight: barSize
    // The tooltip's detail line names the page; without it the tooltip
    // holds no link.
    property bool linked: true
    readonly property Item tip: item.children.find(child => child.pageLinks !== undefined)
    readonly property bool tooltipOpen: tip.opened
    readonly property bool tooltipHovered: tip.opened && tip.tracker.popup.pointerOver
    readonly property int currentLine: tip.currentLine
    readonly property bool itemFocused: item.activeFocus
    // What the frame answered the last link, "" before any.
    property string opened: ""
    // The times a wait as long as two tooltip delays ran out, so the row
    // reads the tooltip after its grace without a sleep of its own.
    property int waits: 0
    Timer { id: wait; interval: 2 * Theme.tooltip.delay; onTriggered: root.waits += 1 }
    function startWait() { wait.restart(); return "ok"; }
    function forget() { opened = ""; return "ok"; }
    function linkLine(value) { linked = value === "true"; return "ok"; }
    // Map a plain tooltip over the stationary pointer on its own item.
    // Compositor map-time refocus forces the first-frame input boundary,
    // without racing a pointer move against expose (VGS-2522).
    property int inputHoverExits: 0
    property int inputShows: 0
    property int inputFrames: 0
    readonly property bool inputHovered: item.hovered
    readonly property bool inputObserved: inputShows > 0 && (inputFrames > 0 || inputHoverExits > 0)
    function overlap() {
        linked = false;
        tip.side = "belowStart";
        tip.box = Qt.binding(() => Qt.rect(0, -item.height - Theme.tooltip.gap, item.width, item.height));
        return "ok";
    }
    Connections {
        target: item
        function onHoveredChanged() { if (!item.hovered) root.inputHoverExits += 1; }
    }
    Connections {
        target: root.tip
        function onOpenedChanged() { if (root.tip.opened) root.inputShows += 1; }
    }
    // Qt queues frameSwapped from the render thread after submitting a
    // frame. The row also captures the compositor before reading hover.
    // https://doc.qt.io/qt-6/qml-qtquick-window.html#frameSwapped-signal
    Connections {
        target: root.tip.opened ? root.tip.tracker.popup.contentItem.Window.window : null
        function onFrameSwapped() { root.inputFrames += 1; }
    }
    function rect(target, box) { const p = target.mapToGlobal(box.x, box.y); return JSON.stringify([p.x, p.y, box.width, box.height]); }
    function itemGeometry() { return rect(item, Qt.rect(0, 0, item.width, item.height)); }
    // The link's words in the bar window's coordinates, read through the
    // popup's own item, as the overlay rows read a popup.
    function linkGeometry() {
        if (!tip.opened) return "closed";
        const pending = [tip.tracker.popup.contentItem];
        while (pending.length > 0) {
            const at = pending.pop();
            if (at.objectName === "tooltipLink") return rect(at, at.linkBox);
            for (const child of at.children) pending.push(child);
        }
        return "absent";
    }
    // The bar holds the keyboard only while a press holds a widget, so the
    // row has the bar's window take it.
    function holdKeyboard(value) {
        QsWindow.window.focusable = value === "true";
        return "ok";
    }
    // The focus a Tab gives the item, and whether the item shows it. A
    // window that turns active focuses its item with another reason, so
    // the focus leaves the item first and the row asks until it shows.
    function focusItem() {
        root.forceActiveFocus();
        item.forceActiveFocus(Qt.TabFocusReason);
        return String(item.visualFocus);
    }
    BarItem {
        id: item
        anchors.verticalCenter: parent.verticalCenter
        iconName: "flask-conical"
        label: "Tip link"
        tooltip: "Idle is not set up"
        tooltipDetails: [root.linked ? "Finish on its [Setup](page:acme.idle/Setup)." : "Finish on its page."]
        onTooltipPageActivated: (page, tab) => root.opened = root.frame.openPage(page, tab)
    }
}
