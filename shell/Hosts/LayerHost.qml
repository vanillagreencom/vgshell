import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Core
import qs.Ui

// Passive layers take no keyboard and restrict pointer input to the
// content's declared mask, so decoration cannot steal application input.
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
                    // A plugin whose manifest sets `glassMaterial` holds only
                    // glass cards here, so while the Glass page's style is
                    // Clear its layer maps under the material namespace
                    // (HyprlandLayer.MATERIAL_NAMESPACES) and its
                    // GlassSurfaces may draw Clear. A layer's namespace is
                    // fixed once it maps, so the choice is read once, in
                    // build(), before the surface maps (`visible` waits for
                    // the content); a layer mapped before Clear was chosen
                    // keeps its namespace and draws Clear's opaque ground
                    // until it maps again.
                    property bool glassMaterial: false
                    WlrLayershell.namespace: glassMaterial ? "vgs:layer-glass" : "vgs:layer"
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

                    // The content's glass plates, when it lends them
                    // (`plateLayer`), in a layer of their own under the
                    // material namespace, so the compositor's layer glass
                    // reaches the plates' faint Clear body and nothing else
                    // the content draws, such as Jarvis's orb
                    // (HyprlandLayer.MATERIAL_NAMESPACES). It maps only
                    // while a plate shows (`platesShown`): Quickshell deletes
                    // a layer's window on every hide and builds a new one on
                    // every show (WlrLayershell::deleteOnInvisible), so the
                    // plates' window lives only while they show. The plates
                    // move here once, keep the content's coordinates, since
                    // both layers cover the same box, and go back to the
                    // content before it goes. Its input region is the
                    // content's `plateInputItems`; `presented` reads as the
                    // content's own layer's does.
                    OverlaySurface {
                        id: plates
                        readonly property Item item: win.content !== null && win.content.plateLayer !== undefined ? win.content.plateLayer : null
                        readonly property bool glassMaterial: true
                        property bool framePresented: false
                        readonly property bool presented: visible && backingWindowVisible && framePresented
                        placement: "center"
                        inset: 0
                        screen: win.targetScreen
                        visible: item !== null && win.visible && !win.hiding && win.content.platesShown === true
                        inputItems: item !== null && win.content.plateInputItems !== undefined ? win.content.plateInputItems : []
                        WlrLayershell.namespace: "vgs:layer-glass"
                        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                        onItemChanged: if (item !== null) item.parent = contentItem
                        onVisibleChanged: framePresented = false
                        onBackingWindowVisibleChanged: framePresented = false

                        Connections {
                            target: plates.item !== null ? plates.item.Window.window : null
                            function onFrameSwapped() {
                                if (plates.visible && plates.backingWindowVisible) plates.framePresented = true;
                            }
                        }
                    }

                    function build() {
                        entry = Layers.entryOf(modelData);
                        if (entry === null) {
                            console.error("layers: no registration for serial " + modelData + ": the host's model ran ahead of Layers.entries");
                            return;
                        }
                        const name = screen ? screen.name : "";
                        glassMaterial = Registry.manifests[entry.pluginId] !== undefined && Registry.manifests[entry.pluginId].glassMaterial === true
                            && Theme.glassStyle === "clear";
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
                        // The plates go back to their content, which
                        // destroys them with it.
                        if (plates.item !== null) plates.item.parent = item;
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
