import QtQuick
import Quickshell
import qs.Core
import qs.Commons
import qs.Ui

// Keep the shell app-id and plugin title available to window rules.
// Hyprland owns the frame and placement; the host draws no decoration.
// Quickshell's floating-window size is an initial request, so the plugin
// must fill the size Hyprland gives it after mapping. Unaccepted keys climb
// to the focused slot, which gives plugins without a key handler Escape.
FloatingWindow {
    id: win

    required property string pluginId
    required property string kind
    required property var request
    signal built(var instance)
    signal dismissed()

    title: Registry.has(pluginId) ? Registry.manifests[pluginId].name : pluginId
    // Set only the initial output. A later payload replaces request, but
    // screen now reports the compositor's current output. Reassigning the
    // original output remaps the native window and emits closed during
    // the hide (Quickshell 0.3.1 ProxyWindowBase::setScreen/onVisibleChanged).
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
    // https://quickshell.org/docs/v0.3.1/guide/qml-language/
    Component.onCompleted: screen = request.screen
    visible: false
    implicitWidth: slot.instance ? Math.max(1, slot.instance.implicitWidth) : 1
    implicitHeight: slot.instance ? Math.max(1, Math.min(Math.max(slot.instance.implicitHeight, paneHeight(slot.instance)), OverlayState.windowRoom(screen).height)) : 1
    // The glass fill while window glass is on (ThemeLogic `hyprland.glass`),
    // so the window takes glass exactly when other windows do. The surface
    // is requested non-opaque, since the colour may turn translucent after
    // the window is created, and an opaque surface format cannot change
    // later (Quickshell 0.3.1 QsWindow `color` and `surfaceFormat`,
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/).
    color: Theme.appearanceState.hyprland.glass ? Theme.glass.glass.fill : Theme.surface.level.raised.background
    surfaceFormat.opaque: false
    onClosed: dismissed()
    // QsWindow's backingWindowVisible means the native window is shown.
    // Request activation then; Compositor waits for its mapped client.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
    onBackingWindowVisibleChanged: if (backingWindowVisible) focusInitial()

    function focusInitial() {
        slot.focusInitial();
        // A menu's trigger also restores its opener's native focus in this
        // turn. Register this target after that restoration; Compositor
        // then waits for any animated opener's actual native-grab release.
        Qt.callLater(() => {
            if (win === null || !backingWindowVisible) return;
            // The current screen follows a user's move; the original
            // summon request still names the screen where it first opened.
            // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
            Plugins.yieldToWindow(win.screen);
            Compositor.activateWindow(win);
        });
    }

    // Implicit sizes flow from children to their host; actual sizes flow
    // back down. Stop at each outer window Pane so its nested content is
    // counted once, including its title space and pinned footer.
    // https://quickshell.org/docs/v0.3.1/guide/size-position/
    function paneHeight(item) {
        if (item instanceof Pane) return item.container === "window" && item.hasTitle ? item.cappedHeight : 0;
        let height = 0;
        for (const child of item.children) {
            if (!child.visible) continue;
            const wanted = paneHeight(child);
            if (wanted > 0) height = Math.max(height, child.y + wanted);
        }
        return height;
    }

    PluginSlot {
        id: slot
        // SummonHost hands a dropped entry's surface no request again.
        listed: win.request !== undefined
        kind: win.kind
        pluginId: win.pluginId
        hostKey: win.kind
        screen: win.screen
        closeOnUnload: true
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.dismissed()
        onBuilt: instance => {
            win.built(instance);
            // The first size request must include positioner/model layout.
            // callLater runs after the bindings in this turn settle.
            // https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method
            Qt.callLater(() => {
                if (win === null || slot === null || slot.instance !== instance) return;
                win.visible = true;
                slot.focusInitial();
            });
        }
        onBuildFailed: key => win.dismissed()
    }
}
