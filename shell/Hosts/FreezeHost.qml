import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Core

// A whole-output, input-transparent still (D115). Map each surface drawing
// nothing first: Quickshell's buffer manager needs a window's render
// formats before its first view can capture (2b4501a buffer/manager.cpp
// initWindow, proxywindow.cpp callOnScenegraphInit). Draw only after every
// output has its frame, so no frame contains a drawn freeze.
//
// ScreencopyView applies the captured frame's transform, not the output's
// current transform, and transposes sourceSize for turned frames (2b4501a
// screencopy/image_copy_capture.cpp and view.cpp onFrameCaptured). Keep
// that upright image in logical output coordinates; never rotate it again.
// live:false captures once; paintCursor selects the pointer in that same
// capture, not a second view:
// https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/ScreencopyView
Scope {
    id: host

    property bool framed: false
    readonly property bool allFramed: surfaces.instances.length > 0
        && surfaces.instances.length === Quickshell.screens.length
        && surfaces.instances.every(surface => surface.hasFrame)
    readonly property bool allPresented: framed && surfaces.instances.length > 0
        && surfaces.instances.every(surface => surface.presented)
    property var run: null

    onAllFramedChanged: if (allFramed && ScreenFreeze.holding) framed = true
    onAllPresentedChanged: {
        if (!allPresented) return;
        ScreenFreeze.shownOn = surfaces.instances.map(surface => surface.screen.name);
        ScreenFreeze.shown = true;
        ScreenFreeze.answer("ok");
    }

    Connections {
        target: ScreenFreeze
        function onHoldingChanged() {
            host.framed = false;
            host.rebuild();
        }
        function onCropRequestChanged() {
            if (ScreenFreeze.cropRequest === null) host.releaseCrop();
            else host.crop(ScreenFreeze.cropRequest);
        }
    }

    // Hide before destroying items with an in-flight grab. Qt 6.12's
    // qquickitemgrabresult.cpp parents the pending result to the item;
    // qsgthreadedrenderloop.cpp hide stops the window's render thread
    // before those items can go. Quickshell 2b4501a otherwise deleteLater()s
    // a still-visible window (proxywindow.cpp deleteWindow).
    property var built: []
    function rebuild() {
        // Keep the cursor choice immutable for each view. Changing
        // paintCursor recreates its capture context (2b4501a view.cpp
        // setPaintCursors), including while a hold is being torn down.
        const next = ScreenFreeze.holding ? Quickshell.screens.map(screen =>
            built.find(entry => entry.screen === screen) || { screen: screen, cursor: ScreenFreeze.cursor }) : [];
        for (const surface of surfaces.instances) {
            if (next.indexOf(surface.modelData) < 0) surface.visible = false;
        }
        built = next;
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (host.run !== null) host.finishCrop("screen-gone");
            host.rebuild();
        }
    }

    function crop(request) {
        const box = request.geometry;
        const parts = [];
        for (const surface of surfaces.instances) {
            const frame = surface.frameGeometry;
            if (!surface.hasFrame || frame === null || !surface.backingWindowVisible) {
                ScreenFreeze.cropped(request, "screen-gone");
                return;
            }
            if (frame.x !== surface.screen.x || frame.y !== surface.screen.y
                    || frame.width !== surface.screen.width || frame.height !== surface.screen.height
                    || frame.scale !== surface.devicePixelRatio) {
                ScreenFreeze.cropped(request, "size");
                return;
            }
            const x = Math.max(box.x, frame.x);
            const y = Math.max(box.y, frame.y);
            const right = Math.min(box.x + box.width, frame.x + frame.width);
            const bottom = Math.min(box.y + box.height, frame.y + frame.height);
            if (right > x && bottom > y) parts.push({ surface: surface, frame: frame, x: x, y: y, width: right - x, height: bottom - y });
        }
        if (parts.length === 0) {
            ScreenFreeze.cropped(request, "geometry");
            return;
        }
        // The highest-scale intersecting output owns the grab window, so
        // Qt's targetSize * window DPR gives the selected device size
        // without a second scale conversion (Qt 6.12
        // qquickitemgrabresult.cpp render).
        const target = parts.reduce((a, b) => a.frame.scale >= b.frame.scale ? a : b);
        const canvas = target.surface.cropCanvas;
        canvas.width = box.width;
        canvas.height = box.height;
        run = { request: request, pieces: [] };
        for (const part of parts) {
            const piece = cropPiece.createObject(canvas, { x: part.x - box.x, y: part.y - box.y, width: part.width, height: part.height });
            if (piece === null) {
                finishCrop("grab");
                return;
            }
            run.pieces.push(piece);
            piece.attach(part);
        }
        const pending = run;
        // One GPU readback of the selection, then one PNG write. No full
        // output image crosses to the CPU (D122).
        if (!canvas.grabToImage(result => {
            if (host.run !== pending || ScreenFreeze.cropRequest !== request) {
                result.destroy();
                return;
            }
            const saved = result.saveToFile(request.path);
            result.destroy();
            host.finishCrop(saved ? "" : "save");
        }, Qt.size(box.width, box.height))) finishCrop("grab");
    }

    function finishCrop(reason) {
        const request = run.request;
        releaseCrop();
        ScreenFreeze.cropped(request, reason);
    }

    function releaseCrop() {
        if (run === null) return;
        const pieces = run.pieces;
        run = null;
        for (const piece of pieces) {
            piece.release();
            piece.destroy();
        }
    }

    Component {
        id: cropPiece
        Item {
            property Item heldView: null
            property Item home: null

            // Clip the held view's drawing, not an intermediate texture.
            // Item.clip also clips its children to its bounds:
            // https://doc.qt.io/qt-6/qml-qtquick-item.html#clip-prop
            clip: true

            function attach(part) {
                home = part.surface.frameItem;
                heldView = part.surface.heldView;
                sourceHome.x = part.frame.x - part.x;
                sourceHome.y = part.frame.y - part.y;
                // Preserve anchors.fill's full-output dimensions while
                // translating the selected intersection to this clip.
                sourceHome.width = part.frame.width;
                sourceHome.height = part.frame.height;
                // The grab renders its window's item tree (Qt 6.12
                // qquickitemgrabresult.cpp setup). Move the existing view,
                // not its capture source: Quickshell 2b4501a view.cpp keeps
                // its held context across reparenting without a capture.
                heldView.parent = sourceHome;
            }

            function release() {
                if (heldView !== null && home !== null) heldView.parent = home;
            }

            // Only the canvas is hidden: the grab includes explicitly
            // visible children (Qt 6.12 qquickwindow.cpp fetchNextNode).
            Item { id: sourceHome }
        }
    }

    Variants {
        id: surfaces
        model: host.built

        PanelWindow {
            id: surface
            required property var modelData
            readonly property bool hasFrame: view.hasContent
            property var frameGeometry: null
            property bool framePresented: false
            readonly property bool presented: frozen.visible && backingWindowVisible && framePresented
            property alias heldView: view
            property alias frameItem: frame
            property alias cropCanvas: canvas

            screen: modelData.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "vgs:freeze"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            onBackingWindowVisibleChanged: framePresented = false

            Connections {
                target: surface.contentItem.Window.window
                function onFrameSwapped() {
                    if (frozen.visible && surface.backingWindowVisible) surface.framePresented = true;
                }
            }

            Item {
                id: frame
                anchors.fill: parent
                visible: false
                ScreencopyView {
                    id: view
                    anchors.fill: parent
                    captureSource: surface.modelData.screen
                    live: false
                    paintCursor: surface.modelData.cursor
                    onHasContentChanged: if (hasContent) surface.frameGeometry = {
                        x: surface.screen.x, y: surface.screen.y, width: surface.screen.width,
                        height: surface.screen.height, scale: surface.devicePixelRatio
                    }
                }
            }

            // A GPU-only snapshot keeps the drawn freeze unchanged while
            // selected views move to one window for the crop. live:false
            // keeps the image even as frame's children move:
            // https://doc.qt.io/qt-6/qml-qtquick-shadereffectsource.html
            ShaderEffectSource {
                id: frozen
                anchors.fill: parent
                sourceItem: host.framed && surface.hasFrame ? frame : null
                live: false
                visible: host.framed && surface.hasFrame
                onVisibleChanged: surface.framePresented = false
            }

            // The shared token is fixed opaque black by ThemeLogic's
            // fixed-background check: image gaps must not change with the
            // theme. grabToImage renders this hidden item (Qt 6.12
            // qquickitemgrabresult.cpp refFromEffectItem).
            Rectangle {
                id: canvas
                visible: false
                color: Theme.screensaver.background
            }
        }
    }
}
