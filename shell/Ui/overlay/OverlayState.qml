pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// Which overlays are open, for the tooltip policy: a tooltip does not open
// while a popover, a menu or a select list is open, so hover under an
// open overlay never raises one. Overlays register on open and leave on
// close, and a bar widget held in a drag registers for the drag; the count
// is what a tooltip reads.
// `grabs` counts the popups that hold the keyboard grab, for the layer
// host, which keeps a passive layer mapped while one is open (LayerHost):
// every overlay `open` counts, and a summoned popup, which registers only
// here so a tooltip inside it still opens. A drag hold counts too, and only
// delays a layer's unmap.
QtObject {
    id: state

    property int open: 0
    property int grabs: 0
    // Typed Item references clear when their item is destroyed (reasontip unit).
    property Item coveredReason: null

    function opened() { open += 1; grabs += 1; }
    function closed() { if (open > 0) open -= 1; if (grabs > 0) grabs -= 1; }
    function grabStarted() { grabs += 1; }
    function grabEnded() { if (grabs > 0) grabs -= 1; }

    // The output `item` draws on, or null while it has none yet. The Qt
    // window an item reports is Quickshell's backing window, which has no
    // `screen`; Quickshell's QsWindow attached object names the Quickshell
    // window, whose `screen` is its output, and answers no window for an
    // item in a plain Qt window (Quickshell 0.3.1, QsWindow attached
    // properties and ProxyWindowAttached::updateWindow).
    function outputOf(item) {
        const window = item === null || item === undefined ? null : item.QsWindow.window;
        return window === null || window === undefined ? null : window.screen;
    }

    // The room an output leaves a surface, as { x, y, width, height } in
    // the output's own logical pixels: its work area, the output less the
    // edges Hyprland reserves for exclusive layers such as the bar, less
    // `size.window.gutter` a side; no bound without an output. The reserved edges are j/monitors' `reserved`, [left, top, right,
    // bottom], from Quickshell's monitor object, whose lastIpcObject "is not
    // updated unless the monitor object is fetched again from Hyprland"
    // (https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandMonitor);
    // Compositor fetches it again as a layer surface opens or closes, and a
    // binding that calls this follows lastIpcObjectChanged. Before Quickshell
    // has read the monitor, nothing is known reserved and the room is the
    // whole output less the gutter. Every overlay, summoned popup and window
    // that sizes itself to its output reads it here.
    function room(output) {
        if (output === null || output === undefined) return { x: 0, y: 0, width: Infinity, height: Infinity };
        const monitor = Hyprland.monitorFor(output);
        const ipc = monitor === null || monitor === undefined ? null : monitor.lastIpcObject;
        const listed = ipc !== null && ipc !== undefined ? ipc.reserved : undefined;
        // A list inside a QVariantMap reaches JS as a Qt sequence, not an
        // Array: Array.isArray answered false for it in the VGS-1178
        // review's C++ probe against Qt 6.11.2, the Qt Quickshell links, so
        // it is copied as an array-like.
        const edges = listed !== null && listed !== undefined && listed.length === 4 ? Array.from(listed) : [];
        const reserved = edges.length === 4 && edges.every(n => typeof n === "number" && isFinite(n)) ? edges : [0, 0, 0, 0];
        const gutter = 2 * Theme.size.window.gutter;
        return {
            x: reserved[0] + gutter / 2,
            y: reserved[1] + gutter / 2,
            width: Math.max(1, output.width - reserved[0] - reserved[2] - gutter),
            height: Math.max(1, output.height - reserved[1] - reserved[3] - gutter)
        };
    }

    // The room under a shell window's pinned top on `output`, as { top,
    // height } in the output's own logical pixels: the top the Hyprland
    // layer's window rule maps every shell window at, `size.window.topShare`
    // of the output's height rounded as that rule's `rint` rounds it
    // (HyprlandLayer.appWindowLines), and the height from there to the
    // bottom of room(output), so a window no taller ends inside the work
    // area; no bound without an output. Every window's map height and the
    // Plugins window's resize read it here.
    function windowRoom(output) {
        if (output === null || output === undefined) return { top: 0, height: Infinity };
        const top = Math.round(Theme.size.window.topShare * output.height);
        const below = room(output);
        return { top: top, height: Math.max(1, below.y + below.height - top) };
    }

    // The widest an overlay anchored to `item` may draw: `cap`, and never
    // wider than its output's room.
    function widthFor(item, cap) {
        return Math.min(cap, room(outputOf(item)).width);
    }
}
