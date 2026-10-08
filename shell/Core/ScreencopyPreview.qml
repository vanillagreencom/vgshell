import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Quickshell 0.3.1 accepts ShellScreen or Toplevel as captureSource.
// HyprlandToplevel.wayland supplies the window's protocol handle.
// https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/ScreencopyView
// https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandToplevel
// The caller's Loader owns this stream and destroys it with its surface.
Item {
    id: root
    property string output: ""
    property string address: ""
    readonly property alias hasContent: view.hasContent
    readonly property alias sourceSize: view.sourceSize
    readonly property rect contentRect: Qt.rect(view.x, view.y, view.width, view.height)
    ScreencopyView {
        id: view
        captureSource: {
            if (root.address !== "") {
                const found = Hyprland.toplevels.values.find(item => item.address === root.address.replace(/^0x/, ""));
                return found === undefined ? null : found.wayland;
            }
            return Quickshell.screens.find(screen => screen.name === root.output) || null;
        }
        live: visible && captureSource !== null
        // Preserve the captured source's aspect ratio inside the caller's box.
        width: hasContent ? Math.min(root.width, root.height * sourceSize.width / sourceSize.height) : root.width
        height: hasContent ? width * sourceSize.height / sourceSize.width : root.height
        x: (root.width - width) / 2
        y: (root.height - height) / 2
    }
}
