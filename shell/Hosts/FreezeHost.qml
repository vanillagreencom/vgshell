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

    function cropParts(box, frames) {
        const parts = [];
        for (const entry of frames) {
            const frame = entry.frame;
            const x = Math.max(box.x, frame.x);
            const y = Math.max(box.y, frame.y);
            const right = Math.min(box.x + box.width, frame.x + frame.width);
            const bottom = Math.min(box.y + box.height, frame.y + frame.height);
            if (right > x && bottom > y) parts.push({ surface: entry.surface, frame: frame, x: x, y: y, width: right - x, height: bottom - y });
        }
        return parts;
    }

    function crop(request) {
        const box = request.geometry;
        const frames = [];
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
            frames.push({ surface: surface, frame: frame });
        }
        let parts = cropParts(box, frames);
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
        run = { request: request, pieces: [], pixelCopy: null, grab: null };
        const pending = run;
        const ratio = target.frame.scale;
        // Qt 6.12.0's native 1x1 flip skips the ownership copy:
        // tmp/vgs2322-qt-defect-facts.md. Remove this special case once
        // the Qt VGS builds against carries the fix; the existing exact-color
        // tiny Capture case must then prove the plain path.
        // qquickitemgrabresult.cpp rounds targetSize * DPR (minimum 1).
        // Its default-size grab of 2/DPR with child Scale 1/(box size * DPR)
        // keeps the original box-center sample at native (pixelX, pixelY).
        // Canvas uses this same window DPR: qt_drawImage copies the native
        // source rect, equal extents skip scaled(), and QPainter cancels
        // matching image/device DPR. Explicit save size copies native 1x1.
        // Both grab roots stay surface-owned until hide stops its render thread.
        const nativePixel = Math.max(1, Math.round(box.width * ratio)) === 1
            && Math.max(1, Math.round(box.height * ratio)) === 1;
        let grabItem = canvas;
        let composition = canvas;
        let footprint = box;
        const pixelX = box.x + 2 * box.width <= target.frame.x + target.frame.width ? 0 : 1;
        const pixelY = box.y + 2 * box.height <= target.frame.y + target.frame.height ? 0 : 1;
        if (nativePixel) {
            grabItem = target.surface.pixelCanvas;
            grabItem.ratio = ratio;
            grabItem.cellWidth = box.width;
            grabItem.cellHeight = box.height;
            composition = grabItem.composition;
            footprint = { x: box.x - pixelX * box.width, y: box.y - pixelY * box.height,
                width: 2 * box.width, height: 2 * box.height };
            parts = cropParts(footprint, frames);
        }
        for (const part of parts) {
            const piece = cropPiece.createObject(composition, { x: part.x - footprint.x, y: part.y - footprint.y, width: part.width, height: part.height });
            if (piece === null) {
                finishCrop("grab");
                return;
            }
            run.pieces.push(piece);
            piece.attach(part);
        }
        const receive = result => {
            if (host.run !== pending || ScreenFreeze.cropRequest !== request) {
                result.destroy();
                return;
            }
            if (nativePixel) {
                pending.grab = result;
                const url = result.url.toString();
                if (url === "") {
                    host.finishCrop("grab");
                    return;
                }
                const copy = pixelCopy.createObject(canvas, { width: Math.ceil(1 / ratio), height: Math.ceil(1 / ratio),
                    sourceUrl: url, sourceX: pixelX, sourceY: pixelY });
                if (copy === null) {
                    host.finishCrop("grab");
                    return;
                }
                pending.pixelCopy = copy;
                copy.pending = pending;
                copy.start();
                return;
            }
            const saved = result.saveToFile(request.path);
            result.destroy();
            host.finishCrop(saved ? "" : "save");
        };
        const started = nativePixel ? grabItem.grabToImage(receive)
            : canvas.grabToImage(receive, Qt.size(box.width, box.height));
        if (!started) finishCrop("grab");
    }

    function finishCrop(reason) {
        const request = run.request;
        releaseCrop();
        ScreenFreeze.cropped(request, reason);
    }

    function releaseCrop() {
        if (run === null) return;
        const pending = run;
        run = null;
        if (pending.pixelCopy !== null) {
            pending.pixelCopy.pending = null;
            pending.pixelCopy.unloadImage(pending.pixelCopy.sourceUrl);
            pending.pixelCopy.destroy();
        }
        if (pending.grab !== null) pending.grab.destroy();
        for (const piece of pending.pieces) {
            piece.release();
            piece.destroy();
        }
    }

    Component {
        id: pixelCopy
        Canvas {
            property var pending: null
            property string sourceUrl: ""
            property int sourceX: 0
            property int sourceY: 0
            property string stage: "new"
            visible: false
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate
            smooth: false
            antialiasing: false

            function isCurrent() {
                return pending !== null && host.run === pending && ScreenFreeze.cropRequest === pending.request;
            }

            function start() {
                if (!isCurrent() || !available || stage !== "new") return;
                stage = "loading";
                loadImage(sourceUrl);
                imageReady();
            }

            function imageReady() {
                if (!isCurrent() || stage !== "loading") return;
                if (isImageError(sourceUrl)) host.finishCrop("grab");
                else if (isImageLoaded(sourceUrl)) {
                    stage = "paint";
                    requestPaint();
                }
            }

            onAvailableChanged: if (available) start()
            onImageLoaded: imageReady()
            onPaint: {
                if (!isCurrent() || stage !== "paint") return;
                stage = "done";
                const ctx = getContext("2d");
                if (ctx === null) {
                    host.finishCrop("grab");
                    return;
                }
                ctx.globalCompositeOperation = "copy";
                ctx.drawImage(sourceUrl, sourceX, sourceY, 1, 1, 0, 0, 1, 1);
                if (!isCurrent()) return;
                const saved = save(pending.request.path, Qt.size(1, 1));
                host.finishCrop(saved ? "" : "save");
            }
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
            property alias pixelCanvas: pixelGrid

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

            Item {
                id: pixelGrid
                property real ratio: 1
                property real cellWidth: 1
                property real cellHeight: 1
                property alias composition: content
                visible: false
                width: 2 / ratio
                height: 2 / ratio

                Rectangle {
                    id: content
                    width: 2 * pixelGrid.cellWidth
                    height: 2 * pixelGrid.cellHeight
                    color: Theme.screensaver.background
                    transform: Scale {
                        xScale: 1 / (pixelGrid.cellWidth * pixelGrid.ratio)
                        yScale: 1 / (pixelGrid.cellHeight * pixelGrid.ratio)
                    }
                }
            }
        }
    }
}
