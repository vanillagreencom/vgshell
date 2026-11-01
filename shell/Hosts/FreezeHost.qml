import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core

// The screen freeze's surfaces (ScreenFreeze, D115): while a plugin holds it,
// one surface per screen on the overlay layer, covering the whole output
// over every reserved zone, taking no keyboard and no pointer, drawing one
// still frame of that screen.
//
// Each surface maps drawing nothing and captures its frame then, so the
// frame holds no freeze; every surface draws its frame in the same turn
// once each screen has one, and a screen added during the hold draws its
// own once it arrives. The surface maps first because a view captures
// only once Quickshell's buffer manager has read a window's render
// formats, and it waits for a window whose scene graph starts after the
// view asks, so the first view in an unmapped window never captures
// (quickshell 2b4501a src/wayland/buffer/manager.cpp initWindow,
// src/window/proxywindow.cpp callOnScenegraphInit). ScreencopyView applies the frame's own transform: it
// prefers ext-image-copy-capture, whose frame carries the output's
// transform, and transposes the source size for a turned frame
// (quickshell 2b4501a src/wayland/screencopy/manager.cpp createContext,
// image_copy_capture.cpp ext_image_copy_capture_frame_v1_transform,
// view.cpp onFrameCaptured), so a rotated output's frame stands upright
// whether the compositor sends it turned (Hyprland 0.56.2) or upright
// (0.57.0, which renders every capture in the normal transform). With
// `live` false the view captures once when its context starts
// (https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/ScreencopyView).
Scope {
    id: host

    // Every surface's frame has arrived; set once per hold, so a screen
    // that joins later does not take the others down.
    property bool framed: false
    readonly property bool allFramed: surfaces.instances.length > 0
        && surfaces.instances.length === Quickshell.screens.length
        && surfaces.instances.every(surface => surface.hasFrame)
    readonly property bool allPresented: framed && surfaces.instances.length > 0
        && surfaces.instances.every(surface => surface.presented)

    onAllFramedChanged: if (allFramed && ScreenFreeze.holding) framed = true
    onAllPresentedChanged: {
        if (!allPresented) return;
        ScreenFreeze.shownOn = surfaces.instances.map(surface => surface.screen.name);
        ScreenFreeze.shown = true;
        ScreenFreeze.answer("ok");
    }

    Connections {
        target: ScreenFreeze
        function onHoldingChanged() { host.framed = false; }
    }

    Variants {
        id: surfaces
        // Built anew at each hold, so each hold captures its own frame: a
        // surface kept past the thaw shows the previous hold's frame
        // (screen-freeze's freshness control).
        model: ScreenFreeze.holding ? Quickshell.screens : []

        PanelWindow {
            id: surface

            required property var modelData
            readonly property bool hasFrame: view.hasContent
            // A frame swapped while the still frame was drawn.
            property bool framePresented: false
            readonly property bool presented: view.visible && backingWindowVisible && framePresented

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // An empty region passes every press through; the selection
            // tool that maps above takes the pointer.
            mask: Region {}
            WlrLayershell.namespace: "vgs:freeze"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            onBackingWindowVisibleChanged: framePresented = false

            Connections {
                target: surface.contentItem.Window.window
                function onFrameSwapped() {
                    if (view.visible && surface.backingWindowVisible) surface.framePresented = true;
                }
            }

            ScreencopyView {
                id: view
                anchors.fill: parent
                captureSource: surface.modelData
                live: false
                visible: host.framed && hasContent
                onVisibleChanged: surface.framePresented = false
            }
        }
    }
}
