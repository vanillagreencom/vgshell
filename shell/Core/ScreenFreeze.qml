pragma Singleton
import QtQuick
import Quickshell

// One instance holds the whole-output still through `screencopy` (D115).
// FreezeHost captures once per output and answers only after all frames show.
// The holder bounds waits: ScreencopyView 0.3.1 exposes hasContent, but no
// failed/stopped signal (src/wayland/screencopy/view.cpp at 2b4501a).
Singleton {
    id: root

    property var holder: null
    readonly property bool holding: holder !== null
    readonly property bool cursor: holder !== null && holder.cursor
    property var shownOn: []
    property bool shown: false
    // At most one selected-box write belongs to the hold.
    property var cropRequest: null

    function freeze(ctx, done, options) {
        if (done !== undefined && typeof done !== "function") throw new Error("refused: freeze=done not-a-function");
        if (options !== undefined) {
            if (options === null || typeof options !== "object" || Array.isArray(options)) throw new Error("refused: freeze=options not-an-object");
            if (Object.keys(options).some(key => key !== "cursor")) throw new Error("refused: freeze=options unknown-key");
            if (options.cursor !== undefined && typeof options.cursor !== "boolean") throw new Error("refused: freeze=cursor not-a-boolean");
        }
        if (holder !== null) return "refused: freeze=busy holder=" + holder.pluginId;
        const entry = { ctx: ctx, pluginId: ctx.id, done: done === undefined ? null : done,
            cursor: options !== undefined && options.cursor === true, release: null };
        entry.release = ctx.onDispose(() => root.end(entry));
        holder = entry;
        return "ok";
    }

    function thaw(ctx) {
        if (holder === null || holder.ctx !== ctx) return "refused: freeze=unheld";
        holder.release();
        return "ok";
    }

    function end(entry) {
        if (holder !== entry) return;
        entry.done = null;
        // Clear pending work before surfaces go: no late grab may write a
        // path whose worker has cancelled and released it.
        cropRequest = null;
        holder = null;
        shownOn = [];
        shown = false;
    }

    function answer(text) {
        if (holder === null || holder.done === null) return;
        const done = holder.done;
        holder.done = null;
        done(text);
    }

    // REVISIT(D122): replace the selected Qt grab if Quickshell lends a
    // held-frame crop directly. The trusted capability holder owns PATH,
    // an already-acquired PNG file, and delegates its write. This is not a
    // file sandbox or a claim that the core acquired the file (D010).
    function crop(ctx, geometry, path, done) {
        if (typeof done !== "function") throw new Error("refused: crop=done not-a-function");
        if (holder === null || holder.ctx !== ctx) return "refused: crop=unheld";
        if (!shown) return "refused: crop=not-ready";
        if (cropRequest !== null) return "refused: crop=busy";
        if (geometry === null || typeof geometry !== "object"
                || !["x", "y", "width", "height"].every(key => Number.isInteger(geometry[key]))
                || geometry.width <= 0 || geometry.height <= 0) return "refused: crop=geometry";
        if (typeof path !== "string" || !path.startsWith("/") || !path.endsWith(".png")) return "refused: crop=path";
        cropRequest = { hold: holder, geometry: { x: geometry.x, y: geometry.y, width: geometry.width, height: geometry.height }, path: path, done: done };
        return "ok";
    }

    function cropped(request, reason) {
        if (cropRequest !== request || holder !== request.hold) return;
        cropRequest = null;
        request.done(reason === "" ? "ok" : "failed: crop=" + reason);
    }

    function record() {
        return { holder: holder === null ? null : holder.pluginId, shown: shown, screens: shownOn.slice().sort(),
            cursor: cursor, cropping: cropRequest !== null };
    }
}
