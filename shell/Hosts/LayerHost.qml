import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Ui

// The passive layer surfaces: one per screen for every registration in
// Layers, each drawing one copy of the plugin's component. The surface
// covers the part of its screen other layers do not reserve and sits on the
// overlay layer and never takes keyboard focus, so it cannot steal input
// from the focused application. Pointer input reaches it only where its
// content says: the whole surface while the content's `inputAll` is true,
// otherwise the union of its
// `inputItems`, and nowhere without any. The
// core assigns the content its `screen` after creation; a content without
// that property is not built, logged, and maps no surface. A screen that
// goes takes its surfaces with it.
//
// A surface whose content stops being shown while a popup holds the
// keyboard grab (OverlayState.grabs) stays mapped, its content hidden and
// its mask empty, until the last grab ends. Hyprland 0.56.2
// LayerSurface.cpp CLayerSurface::onUnmap gives keyboard focus to
// focusState()->surface() when the unmapping layer had neither keyboard nor
// pointer focus, ignoring the xdg_popup grab: the popup stays open and its
// keys go to the main window. Remove when a Hyprland release that VGS
// requires stops returning keyboard focus to the main window when an
// on-screen display closes while a popup holds it, checked against
// Hyprland's own changelog or code. The content hides when its plugin says;
// only the unmap waits. Known limit: a release, disable or reload during a
// grab destroys the surface, and Hyprland still moves the keyboard then.
Scope {
    id: host

    Component.onCompleted: Plugins.registerHost("layer", host)

    // Every screen keeps its scope, surfaces or none, so a registration that
    // ends as another begins never tears a scope down while its inner
    // Variants still answers the new one.
    Variants {
        model: Quickshell.screens

        Scope {
            id: onScreen

            required property var modelData

            Variants {
                model: Layers.serials

                OverlaySurface {
                    id: win

                    required property int modelData
                    // Read once, not bound: the entry leaves Layers before its
                    // surface goes.
                    property var entry: null
                    property Item content: null
                    property var targetScreen: onScreen.modelData
                    property bool framePresented: false
                    readonly property bool shown: content !== null && (content.shown === undefined || content.shown === true)
                    // Mapped past `shown` while a grab is open; set only by
                    // a grab or a map, never by the drop of `shown`.
                    property bool held: false
                    // Mapped only by the hold: nothing drawn, no input.
                    readonly property bool hiding: held && !shown
                    readonly property bool presented: !hiding && visible && backingWindowVisible && framePresented
                    // The screen name the content was built on, kept while the
                    // screen itself reads null during teardown.
                    property string builtOn: ""
                    placement: "center"
                    inset: 0
                    inputAll: !hiding && content !== null && content.inputAll === true
                    inputItems: !hiding && content !== null && content.inputItems !== undefined ? content.inputItems : []
                    screen: targetScreen
                    // `shown` is independent of Item.visible, which inherits
                    // the hidden host and cannot request that host's map.
                    visible: targetScreen !== null && content !== null && (shown || held)
                    // The host's item, not the plugin's root, which may bind
                    // its own `visible`.
                    contentItem.visible: !hiding
                    WlrLayershell.namespace: "vgs:layer"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    Component.onCompleted: build()
                    Component.onDestruction: drop()
                    onVisibleChanged: {
                        framePresented = false;
                        if (visible && OverlayState.grabs > 0) held = true;
                    }
                    onHidingChanged: framePresented = false
                    onBackingWindowVisibleChanged: framePresented = false
                    onContentChanged: framePresented = false

                    Connections {
                        target: win.content !== null ? win.content.Window.window : null
                        function onFrameSwapped() {
                            if (win.visible && win.backingWindowVisible) win.framePresented = true;
                        }
                    }

                    Connections {
                        target: Layers
                        function onReleased(serial) { if (serial === win.modelData) win.drop(); }
                    }

                    // The last grab ends inside the popup's onVisibleChanged:
                    // Qt QWindowPrivate::setVisible emits visibleChanged
                    // before platformWindow->setVisible(false), so the
                    // xdg_popup is destroyed only after this handler. The
                    // release waits a turn, so the popup's destroy reaches
                    // Hyprland before the layer's unmap.
                    Connections {
                        target: OverlayState
                        function onGrabsChanged() {
                            if (OverlayState.grabs > 0) {
                                if (win.visible) win.held = true;
                            } else {
                                Qt.callLater(win.release);
                            }
                        }
                    }

                    function release() {
                        if (OverlayState.grabs === 0) held = false;
                    }

                    function build() {
                        entry = Layers.entryOf(modelData);
                        if (entry === null) {
                            console.error("layers: no registration for serial " + modelData + ": the host's model ran ahead of Layers.entries");
                            return;
                        }
                        const name = screen ? screen.name : "";
                        const item = entry.component.createObject(win.contentItem);
                        if (item === null) {
                            console.error("layers: " + entry.pluginId + " content not built on " + name + ": createObject answered null");
                            return;
                        }
                        try {
                            item.screen = Qt.binding(() => win.targetScreen);
                            item.anchors.fill = win.contentItem;
                        } catch (e) {
                            console.error("layers: " + entry.pluginId + " content not built on " + name + ": " + e.message);
                            item.destroy();
                            return;
                        }
                        content = item;
                        builtOn = name;
                        entry.screens[name] = item;
                    }

                    function drop() {
                        if (content === null || entry === null) return;
                        const item = content;
                        content = null;
                        if (entry.screens[builtOn] === item) delete entry.screens[builtOn];
                        builtOn = "";
                        item.destroy();
                    }
                }
            }
        }
    }
}
