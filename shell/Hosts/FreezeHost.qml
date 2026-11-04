import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import "../Core/FreezeBands.js" as Bands

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
//
// A hold that asks for the still gets its frames written (D118) once every
// screen shows its frame and ScreenFreeze made the hold's directory: one
// chain of bands over every screen, each band a hidden ShaderEffectSource
// over a strip of the saved view, grabbed and saved as PPM. Each band's
// callback asks for the next band before it saves its own, and a grab
// completes only on its window's next frame (Qt 6.12
// qquickitemgrabresult.cpp: create requests window()->update(), the image
// comes from afterRendering and the callback from a posted event), so one
// GUI turn saves one band of at most FreezeBands.BAND_PIXELS.
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
    readonly property bool cursor: ScreenFreeze.cursor
    // The hold's band chain once started: { serial, jobs, screens, done }.
    property var chain: null
    readonly property bool stillReady: allPresented && ScreenFreeze.frameDir !== ""

    onAllFramedChanged: if (allFramed && ScreenFreeze.holding) framed = true
    onAllPresentedChanged: {
        if (!allPresented) return;
        ScreenFreeze.shownOn = surfaces.instances.map(surface => surface.screen.name);
        ScreenFreeze.shown = true;
        ScreenFreeze.answer("ok");
    }
    onStillReadyChanged: if (stillReady && chain === null) startStill()

    Connections {
        target: ScreenFreeze
        function onHoldingChanged() {
            host.framed = false;
            host.chain = null;
            host.rebuild();
        }
    }

    // The screens the surfaces stand on: every screen while a hold lasts,
    // none otherwise, so each hold builds its surfaces anew. A surface's
    // window is hidden before the surface goes: quickshell 2b4501a's
    // ~ProxyWindowBase deleteLater()s a window it leaves visible while the
    // surface's items, a band's pending grab result among them, go at once
    // (src/window/proxywindow.cpp deleteWindow), and the render thread could
    // then finish that grab on a deleted result. Hiding the window stops its
    // render thread first (Qt 6.12 qsgthreadedrenderloop.cpp hide:
    // handleObscurity and releaseResources wait on it).
    property var built: []
    function rebuild() {
        const next = ScreenFreeze.holding ? Quickshell.screens.slice() : [];
        for (const surface of surfaces.instances) {
            if (next.indexOf(surface.modelData) < 0) surface.visible = false;
        }
        built = next;
    }

    // A screen that leaves while its bands are written takes its window,
    // and the grab result parented to its band, with it, so its callback
    // never comes (Qt 6.12 qquickitemgrabresult.cpp create parents the
    // result to the item).
    Connections {
        target: Quickshell
        function onScreensChanged() {
            const run = host.chain;
            if (run !== null && !run.done) {
                const names = Quickshell.screens.map(screen => screen.name);
                if (run.screens.some(screen => names.indexOf(screen.name) < 0)) host.stillFailed(run, "screen-gone");
            }
            host.rebuild();
        }
    }

    // Each screen writes a frame at its own ratio and at every greater one
    // in the layout, keyed by the ratio in 120ths, so a box over screens of
    // mixed scales is cropped at the greatest scale it meets, as `grim -g`
    // renders one.
    function startStill() {
        const shown = surfaces.instances.slice().sort((a, b) => a.screen.name < b.screen.name ? -1 : a.screen.name > b.screen.name ? 1 : 0);
        // wp-fractional-scale-v1 gives the ratio in 120ths.
        const ratios = shown.map(surface => Math.round(surface.devicePixelRatio * 120));
        const all = ratios.filter((ratio, i) => ratios.indexOf(ratio) === i).sort((a, b) => a - b);
        const run = { serial: ScreenFreeze.serial, jobs: [], screens: [], done: false };
        chain = run;
        for (let i = 0; i < shown.length; i += 1) {
            const screen = shown[i].screen;
            const entry = { name: screen.name, x: screen.x, y: screen.y, width: screen.width, height: screen.height, frames: [] };
            run.screens.push(entry);
            for (const at of all.filter(ratio => ratio >= ratios[i])) {
                const plan = Bands.frame(screen.width, screen.height, ratios[i], at);
                const frame = { ratio: at, width: plan.width, height: plan.height, bands: [] };
                entry.frames.push(frame);
                plan.bands.forEach((band, k) => run.jobs.push({ screen: screen.name, own: ratios[i], logical: [screen.width, screen.height], frame: frame, band: band,
                    targetWidth: plan.targetWidth, path: ScreenFreeze.frameDir + "/" + i + "-" + at + "-" + k + ".ppm" }));
            }
        }
        grab(run, 0);
    }

    // A band is grabbed only from the screen it was planned for: a screen
    // whose ratio or size changed since would give a band of another size.
    function grab(run, index) {
        const job = run.jobs[index];
        const surface = surfaces.instances.find(candidate => candidate.screen.name === job.screen);
        if (surface === undefined) {
            stillFailed(run, "screen-gone");
            return;
        }
        if (Math.round(surface.devicePixelRatio * 120) !== job.own || surface.screen.width !== job.logical[0] || surface.screen.height !== job.logical[1]) {
            stillFailed(run, "size");
            return;
        }
        const asked = Date.now();
        if (!surface.grabBand(job, result => host.banded(run, index, result, asked))) stillFailed(run, "grab");
    }

    function banded(run, index, result, asked) {
        const back = Date.now();
        if (chain !== run || run.done) {
            result.destroy();
            return;
        }
        const job = run.jobs[index];
        const last = index + 1 === run.jobs.length;
        if (!last) grab(run, index + 1);
        // QImage::save writes PPM by the suffix, `P6 <width> <height> 255`
        // and RGB rows (the nested measurement read `P6\n6016 3384\n255\n`).
        const saved = result.saveToFile(job.path);
        const done = Date.now();
        // destroy() frees the result's image at once, not at the next
        // garbage collection (VGS-2232 round-3 host bench, Qt 6.12.0).
        result.destroy();
        if (!saved) {
            stillFailed(run, "save");
            return;
        }
        job.frame.bands.push({ path: job.path, rows: job.band.height });
        ScreenFreeze.noteBand(run.serial, { screen: job.screen, ratio: job.frame.ratio, frame: job.frame.width + "x" + job.frame.height, rows: job.band.height,
            askedAt: asked, readbackMs: back - asked, saveMs: done - back });
        if (!last || run.done) return;
        run.done = true;
        ScreenFreeze.stillWritten(run.serial, { screens: run.screens });
    }

    function stillFailed(run, reason) {
        if (run.done) return;
        run.done = true;
        ScreenFreeze.stillFailed(run.serial, reason);
    }

    Variants {
        id: surfaces
        // Built anew at each hold, so each hold captures its own frame: a
        // surface kept past the thaw shows the previous hold's frame
        // (screen-freeze's freshness control).
        model: host.built

        PanelWindow {
            id: surface

            required property var modelData
            // With the cursor asked, a screen counts as framed only once
            // its pointer frame is in too, so that frame is taken before
            // any freeze shows and holds none.
            readonly property bool hasFrame: view.hasContent && (!host.cursor || cursorView.hasContent)
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

            // JOB's band of the saved view, grabbed at the band's target
            // size; DONE gets the ItemGrabResult. False when Qt refuses
            // the grab.
            function grabBand(job, done) {
                band.sourceRect = Qt.rect(0, job.band.y, surface.screen.width, job.band.rows);
                band.textureSize = Qt.size(job.frame.width, job.band.height);
                band.width = job.targetWidth;
                band.height = job.band.targetHeight;
                return band.grabToImage(done, Qt.size(job.targetWidth, job.band.targetHeight));
            }

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

            // The pointer for the saved frames: the same screen captured
            // once more with the pointer drawn, never shown, so the freeze
            // a person sees has no still pointer under the selector's. A
            // view captures whether or not it is visible (quickshell
            // 2b4501a view.cpp: componentComplete and createContext read
            // no visibility).
            ScreencopyView {
                id: cursorView
                anchors.fill: parent
                captureSource: host.cursor ? surface.modelData : null
                live: false
                paintCursor: true
                visible: false
            }

            // One band of the saved view. A ShaderEffectSource takes its
            // source by reference whether or not either is visible, so the
            // hidden pointer view renders into it (Qt 6.12
            // qquickshadereffectsource.cpp setSourceItem), and a grab
            // renders a hidden item (qquickitemgrabresult.cpp create
            // references it the same way). Its texture is the band's
            // device size, so it samples the view one to one.
            ShaderEffectSource {
                id: band
                visible: false
                sourceItem: host.cursor ? cursorView : view
            }
        }
    }
}
