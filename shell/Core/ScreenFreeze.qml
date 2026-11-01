pragma Singleton
import QtQuick
import Quickshell

// The screen freeze a plugin holds through capability `screencopy`: one
// still frame of every screen, drawn over everything on a surface that
// covers the whole output, while a selection tool maps above it. One
// plugin instance holds it at a time; FreezeHost draws it. Each surface
// captures its frame before it maps, so no frame holds a freeze surface,
// and the surfaces map together once every screen has its frame. The hold
// ends with `thaw`, the instance's teardown, or a disable.
Singleton {
    id: root

    // { serial, pluginId, done } while held, else null. `done` is the
    // holder's callback until its one answer, then null.
    property var holder: null
    property int serial: 0
    readonly property bool holding: holder !== null
    // Set by FreezeHost: the screens drawing their frame, and whether every
    // screen's surface showed it.
    property var shownOn: []
    property bool shown: false

    // Hold the freeze for the instance `ctx` belongs to. `done(answer)`,
    // when given, is called once with `ok` once every screen shows its
    // still frame. A screen whose capture never delivers a frame leaves it
    // uncalled: Quickshell 0.3.1's ScreencopyView reports no failed or
    // stopped capture (view.cpp emits no `stopped`), so the holder bounds
    // its wait. Answers `ok` once held.
    function freeze(ctx, done) {
        if (done !== undefined && typeof done !== "function") throw new Error("refused: freeze=done not-a-function");
        if (holder !== null) return "refused: freeze=busy holder=" + holder.pluginId;
        serial += 1;
        const entry = { serial: serial, pluginId: ctx.id, done: done === undefined ? null : done, release: null };
        entry.release = ctx.onDispose(() => root.end(entry));
        holder = entry;
        return "ok";
    }

    function thaw(ctx) {
        if (holder === null || holder.pluginId !== ctx.id) return "refused: freeze=unheld";
        // The disposer runs `end` and leaves the instance's teardown nothing.
        holder.release();
        return "ok";
    }

    function end(entry) {
        if (holder !== entry) return;
        entry.done = null;
        holder = null;
        shownOn = [];
        shown = false;
    }

    // FreezeHost's report that the current hold shows on every screen.
    function answer(text) {
        if (holder === null || holder.done === null) return;
        const done = holder.done;
        holder.done = null;
        done(text);
    }

    function record() {
        return { holder: holder === null ? null : holder.pluginId, shown: shown, screens: shownOn.slice().sort() };
    }
}
