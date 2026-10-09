import QtQuick
import Quickshell
import qs.Core
import qs.Commons
import qs.Ui

// An application window: a summon of kind `window`, built as a Hyprland
// toplevel. Its class is the shell's one app-id, which shell.qml's AppId
// pragma sets, and its title is the plugin's manifest name, so the user's
// window rules and keybinds find it; the Hyprland layer's `vgs:window` rule
// floats it and centres it. It draws no border and no radius of its own, so
// Hyprland's decoration is the frame. The window maps once the plugin is
// built, at the larger of the plugin's request and its window Pane's
// content height, bounded by the output's room. Quickshell sends a floating window
// no size change once it is shown, so that size is the first request only,
// and the plugin fills whatever size Hyprland gives the window after. A
// close through Hyprland, such as its killactive key, is `dismissed`, which
// the host treats as a hide, and so is an Escape the plugin leaves
// unaccepted while the window has the keyboard: the slot holds the focus
// the plugin takes none of, and a key the focused item does not accept
// climbs its parents to the slot.
FloatingWindow {
    id: win

    required property string pluginId
    required property string kind
    required property var request
    signal built(var instance)
    signal dismissed()

    title: Registry.has(pluginId) ? Registry.manifests[pluginId].name : pluginId
    screen: request ? request.screen : null
    visible: false
    implicitWidth: slot.instance ? Math.max(1, slot.instance.implicitWidth) : 1
    implicitHeight: slot.instance ? Math.max(1, Math.min(Math.max(slot.instance.implicitHeight, paneHeight(slot.instance)), OverlayState.room(screen).height)) : 1
    color: Theme.surface.level.raised.background
    onClosed: dismissed()

    function focusInitial() {
        slot.focusInitial();
    }

    // Implicit sizes flow from children to their host; actual sizes flow
    // back down. Stop at each outer window Pane so its nested content is
    // counted once, including its title space and pinned footer.
    // https://quickshell.org/docs/v0.3.1/guide/size-position/
    function paneHeight(item) {
        if (item instanceof Pane) return item.container === "window" && item.hasTitle ? item.uncappedHeight : 0;
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
