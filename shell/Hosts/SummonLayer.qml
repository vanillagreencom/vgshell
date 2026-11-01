import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons
import qs.Ui

// A summon with no anchor, built as a layer surface on the screen it was
// summoned on. An overlay covers its screen and owns the keyboard until it
// closes, and tells Compositor so, whose reveal waits until it is gone. A
// panel or a menu covers its screen too, the reserved space included only
// for `center`, and sits inside at the plugin's implicit size
// and its `placement` setting (PluginLogic.surfacePlacement); a press on
// the rest of the surface, over a window or the empty desktop, is
// `dismissed`, which the host treats as a hide; a press inside the plugin's
// box that none of its controls takes closes nothing. A popup the plugin
// opens is its own surface above this one, so a press on it reaches the
// popup. The keyboard stays on demand, so a window that takes it closes
// nothing here. An Escape the plugin leaves unaccepted is `dismissed` too.
// Every other screen holds a press catcher while a panel or a menu shows,
// so a press there is `dismissed` as well. An overlay's plugin owns a press
// beside its content (the launcher closes, an authentication dialog keeps
// its request), so a press on another screen reaches an overlay's plugin
// only through its `pressedOnOtherScreen()`, when it has one.
PanelWindow {
    id: win

    required property string pluginId
    required property string kind
    required property var request
    signal built(var instance)
    signal dismissed()

    readonly property var place: {
        const settings = Registry.settingsOf(pluginId);
        return PluginLogic.surfacePlacement(kind, settings, Theme.space.md);
    }
    readonly property bool catches: PluginLogic.layerCatchesOutside(kind)

    screen: request ? request.screen : null
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: place.exclusion === "ignore" ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "vgs:" + kind
    readonly property int shellLayer: place.layer === "top" ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.layer: shellLayer
    readonly property bool exclusiveKeyboard: PluginLogic.layerKeyboardFocus(kind, false) === "exclusive"
    WlrLayershell.keyboardFocus: exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    // Compositor's record of this surface while it holds the keyboard.
    property var keyboardRelease: null

    Component.onCompleted: {
        if (place.error !== "") console.error("summon host: " + pluginId + " " + place.error);
        if (exclusiveKeyboard) keyboardRelease = Compositor.keyboardLayer();
    }
    // The release stays with the destruction, which every way out reaches.
    // The host unmaps the surface before it drops it, so the release
    // follows the unmap, and Compositor's reveal reads the state after it.
    Component.onDestruction: if (keyboardRelease !== null) keyboardRelease()

    // Take the surface off the screen ahead of its teardown. Quickshell
    // hides a layer surface's Qt window when `visible` goes false and
    // deletes that window on a later turn of the event loop
    // (WlrLayershell::deleteOnInvisible and
    // ProxyWindowBase::setVisibleDirect, src/window/proxywindow.cpp). A
    // surface left to its destruction stays mapped until the end of that
    // deletion, the scene graph teardown, which held the GUI thread 19 to
    // 24 ms in five theme changes (event-loop marks and
    // qt.scenegraph.time.renderloop in the theme-latency row, cachy,
    // 2026-10-10, load 9.6 to 11.8, CPU pressure 0.3 to 4.5%).
    function unmap() {
        visible = false;
    }

    function focusInitial() {
        slot.focusInitial();
    }

    // keyboard-path: Escape closes the summon through the slot below
    // pointer-cursor-exempt: a press here is a press beside the open summon, not a control
    MouseArea {
        anchors.fill: parent
        enabled: win.catches
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (!sized.contains(mapToItem(sized, mouse.x, mouse.y)))
                win.dismissed();
        }
    }

    // A Hyprland focus grab would see a press on any screen, but Hyprland
    // keeps one seat grab at a time: a popup the plugin opens with a grab
    // replaces it, and the replaced focus grab sends `cleared` (Hyprland
    // v0.56.2 CXDGShellProtocol::addOrStartGrab, CSeatManager::setGrab,
    // CFocusGrab's onEnd), which would close the surface as its popup
    // opens. Hyprland v0.57.0 mouseMoveUnified hit-tests the pointer's
    // monitor's layers (InputManager.cpp:435-446); Exclusive holds only the
    // keyboard. Catch every other-screen press on that screen instead of
    // relying on an item outside this window. WlrKeyboardFocus.None takes
    // no keyboard input (Quickshell 0.3.1 WlrKeyboardFocus reference).
    // The catcher keeps this surface's layer and reserved space.
    readonly property bool otherScreenPress: exclusiveKeyboard && slot.instance !== null && typeof slot.instance.pressedOnOtherScreen === "function"
    readonly property var otherScreens: catches || otherScreenPress ? Quickshell.screens.filter(s => s !== win.screen) : []
    Variants {
        model: win.otherScreens

        PanelWindow {
            required property var modelData
            screen: modelData
            // Quickshell.screens drops a removed screen before Qt moves its
            // windows to another screen and Variants deletes this one on a
            // later turn; hidden first, it is never remapped there
            // (BarHost, VGS-1104).
            visible: win.visible && Quickshell.screens.indexOf(modelData) !== -1
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: win.exclusionMode
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "vgs:" + win.kind + "-outside"
            WlrLayershell.layer: win.shellLayer
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // keyboard-path: Escape closes the summon on its own screen
            // pointer-cursor-exempt: a press here is a press beside the open summon, not a control
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: {
                    if (win.catches) win.dismissed();
                    else if (win.otherScreenPress) slot.instance.pressedOnOtherScreen();
                }
            }
        }
    }

    // The plugin's box: its height follows the plugin's through
    // SurfaceHeight, so a content change animates; the layer surface itself
    // covers the screen and never resizes.
    SurfaceHeight {
        id: sized
        // The room inside the margins; a plugin larger than it is laid out
        // at the room's size.
        readonly property real roomWidth: Math.max(1, win.width - win.place.margins.left - win.place.margins.right)
        readonly property real roomHeight: Math.max(1, win.height - win.place.margins.top - win.place.margins.bottom)
        width: !win.catches ? win.width : slot.instance ? Math.max(1, Math.min(slot.instance.implicitWidth, roomWidth)) : 1
        target: !win.catches ? win.height : slot.instance ? Math.max(1, Math.min(slot.instance.implicitHeight, roomHeight)) : 1
        x: !win.catches ? 0 : win.place.anchors.left === win.place.anchors.right ? Math.round((win.width - width) / 2) : win.place.anchors.left ? win.place.margins.left : win.width - width - win.place.margins.right
        y: !win.catches ? 0 : win.place.anchors.top === win.place.anchors.bottom ? Math.round((win.height - height) / 2) : win.place.anchors.top ? win.place.margins.top : win.height - height - win.place.margins.bottom

        PluginSlot {
            id: slot
            // SummonHost hands a dropped entry's surface no request again.
            listed: win.request !== undefined
            kind: win.kind
            pluginId: win.pluginId
            hostKey: win.kind
            settingsPage: Registry.settingsPageOf(win.kind, win.pluginId)
            screen: win.screen
            closeOnUnload: true
            focus: true
            anchors.fill: parent
            Keys.onEscapePressed: win.dismissed()
            onBuilt: instance => win.built(instance)
            onBuildFailed: key => win.dismissed()
        }
    }
}
