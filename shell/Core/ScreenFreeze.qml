pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The screen freeze a plugin holds through capability `screencopy`: one
// still frame of every screen, drawn over everything on a surface that
// covers the whole output, while a selection tool maps above it. One
// plugin instance holds it at a time; FreezeHost draws it. Each surface
// captures its frame before it maps, so no frame holds a freeze surface,
// and the surfaces map together once every screen has its frame. The hold
// ends with `thaw`, the instance's teardown, or a disable.
//
// A holder that asks for the still also gets the held frame as files
// (D118): FreezeHost writes each screen's frame as PPM bands into the
// hold's own directory, `<frameRoot>/<serial>`, mode 0700, which this
// singleton makes for the hold and removes when the hold ends. It owns
// `frameRoot` alone: one shell runs per XDG_RUNTIME_DIR, since bin/vgshell
// holds $XDG_RUNTIME_DIR/vgshell.lock (docs/architecture/runtime.md
// § Process).
Singleton {
    id: root

    // { serial, pluginId, done, still, cursor, dir, made, release } while
    // held, else null. `done` and `still` are the holder's callbacks until
    // their one answer, then null; `made` is whether the hold's directory
    // was made.
    property var holder: null
    property int serial: 0
    readonly property bool holding: holder !== null
    // Whether the hold's saved frames carry the pointer.
    readonly property bool cursor: holder !== null && holder.cursor
    // Set by FreezeHost: the screens drawing their frame, and whether every
    // screen's surface showed it.
    property var shownOn: []
    property bool shown: false
    // The hold's frame directory once made, else "": FreezeHost writes
    // there.
    property string frameDir: ""
    // The hold's still for the record: { state, startedAt, writtenAt, bands }, or null.
    property var still: null

    // Quickshell.env answers null for an unset variable (quickshell 2b4501a
    // src/core/qmlglobal.cpp env). An unset or relative value names no
    // directory, so nothing is made or removed under it.
    readonly property string frameRoot: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return typeof dir === "string" && dir.startsWith("/") ? dir + "/vgshell/freeze" : "";
    }
    // Whether this shell cleared frameRoot of what an earlier shell left.
    property bool rootCleared: false
    // File steps, { kind: "prepare"|"remove", entry }, run one at a time,
    // so a hold's removal runs after its own directory was made.
    property var steps: []

    // Hold the freeze for the instance `ctx` belongs to. `done(answer)`,
    // when given, is called once with `ok` once every screen shows its
    // still frame. A screen whose capture never delivers a frame leaves it
    // uncalled: Quickshell 0.3.1's ScreencopyView reports no failed or
    // stopped capture (view.cpp emits no `stopped`), so the holder bounds
    // its wait. `options.still(answer)`, when given, is called at most once,
    // never after the hold ends, with the written frames or
    // `failed: still=<reason>`. A hold whose frame never shows leaves it
    // uncalled as it leaves `done`, and so does a band grab that never
    // returns, a window that stops rendering among them (FreezeHost.qml),
    // so the holder bounds this wait too. `options.cursor` puts the pointer
    // in the written frames.
    // Answers `ok` once held.
    function freeze(ctx, done, options) {
        if (done !== undefined && typeof done !== "function") throw new Error("refused: freeze=done not-a-function");
        if (options !== undefined) {
            if (options === null || typeof options !== "object" || Array.isArray(options)) throw new Error("refused: freeze=options not-an-object");
            if (options.still !== undefined && typeof options.still !== "function") throw new Error("refused: freeze=still not-a-function");
            if (options.cursor !== undefined && typeof options.cursor !== "boolean") throw new Error("refused: freeze=cursor not-a-boolean");
            if (options.cursor !== undefined && options.still === undefined) throw new Error("refused: freeze=cursor without-still");
        }
        if (holder !== null) return "refused: freeze=busy holder=" + holder.pluginId;
        serial += 1;
        const still = options !== undefined && options.still !== undefined ? options.still : null;
        const entry = { serial: serial, pluginId: ctx.id, done: done === undefined ? null : done, still: still,
            cursor: still !== null && options.cursor === true, dir: "", made: false, release: null };
        entry.release = ctx.onDispose(() => root.end(entry));
        holder = entry;
        if (still !== null) prepare(entry);
        return "ok";
    }

    function thaw(ctx) {
        if (holder === null || holder.pluginId !== ctx.id) return "refused: freeze=unheld";
        // The disposer runs `end` and leaves the instance's teardown nothing.
        holder.release();
        return "ok";
    }

    // The holder goes first, so a band FreezeHost finishes after this sees
    // another hold and writes nothing.
    function end(entry) {
        if (holder !== entry) return;
        entry.done = null;
        entry.still = null;
        holder = null;
        shownOn = [];
        shown = false;
        frameDir = "";
        still = null;
        if (entry.dir !== "") queue({ kind: "remove", entry: entry });
    }

    // FreezeHost's report that the current hold shows on every screen.
    function answer(text) {
        if (holder === null || holder.done === null) return;
        const done = holder.done;
        holder.done = null;
        done(text);
    }

    function prepare(entry) {
        still = { state: "preparing", startedAt: 0, writtenAt: 0, bands: [] };
        if (frameRoot === "") {
            stillFailed(entry.serial, "runtime-dir");
            return;
        }
        entry.dir = frameRoot + "/" + entry.serial;
        queue({ kind: "prepare", entry: entry });
    }

    function queue(step) {
        steps = steps.concat([step]);
        runStep();
    }

    function runStep() {
        while (steps.length > 0 && !files.running) {
            const step = steps[0];
            // A hold that ended before its turn needs no directory, and a
            // directory never made is not this shell's to remove.
            if (step.kind === "prepare" ? holder !== step.entry : !step.entry.made) {
                steps = steps.slice(1);
                continue;
            }
            // `mkdir -m` without -p refuses a directory that exists, so a
            // hold never reuses one. The first hold after a start removes
            // what a crashed shell left before it makes its own.
            files.command = step.kind === "remove" ? ["rm", "-rf", "--", step.entry.dir]
                : rootCleared ? ["mkdir", "-m", "0700", "--", step.entry.dir]
                : ["bash", "-c", "rm -rf -- \"$1\" && mkdir -p -m 0700 -- \"$1\" && mkdir -m 0700 -- \"$2\"", "vgs-freeze", root.frameRoot, step.entry.dir];
            files.running = true;
            return;
        }
    }

    function stepDone(ok, detail) {
        const step = steps[0];
        steps = steps.slice(1);
        if (step.kind === "prepare") {
            if (ok) {
                rootCleared = true;
                step.entry.made = true;
            }
            if (holder === step.entry) {
                if (ok) {
                    still = Object.assign({}, still, { state: "writing", startedAt: Date.now() });
                    frameDir = step.entry.dir;
                } else {
                    console.error("freeze: mkdir=failed path=" + step.entry.dir + " " + detail);
                    stillFailed(step.entry.serial, "mkdir");
                }
            }
        } else if (!ok) {
            console.error("freeze: remove=failed path=" + step.entry.dir + " " + detail);
        }
        runStep();
    }

    // FreezeHost's reports on the hold numbered SERIAL; a report on a hold
    // that ended goes nowhere.
    function noteBand(serial, band) {
        if (holder === null || holder.serial !== serial || still === null) return;
        still = Object.assign({}, still, { bands: still.bands.concat([band]) });
    }

    function stillWritten(serial, frames) {
        if (holder === null || holder.serial !== serial || holder.still === null) return;
        const call = holder.still;
        holder.still = null;
        still = Object.assign({}, still, { state: "written", writtenAt: Date.now() });
        call(frames);
    }

    function stillFailed(serial, reason) {
        if (holder === null || holder.serial !== serial || holder.still === null) return;
        const call = holder.still;
        holder.still = null;
        still = Object.assign({}, still, { state: "failed: still=" + reason });
        call("failed: still=" + reason);
    }

    function record() {
        return { holder: holder === null ? null : holder.pluginId, shown: shown, screens: shownOn.slice().sort(),
            still: still === null ? null : Object.assign({ dir: holder.dir, cursor: holder.cursor }, still) };
    }

    // The patched engine ends this Process with the shell
    // (docs/architecture/runtime.md § Process). Quickshell 2b4501a emits
    // `exited` only for a process that ran, and `runningChanged` after it
    // or alone for one that failed to start (src/io/process.cpp
    // onFinished, onErrorOccurred), so the step ends on runningChanged.
    // onFinished calls the collector's streamEnded before either signal, so
    // its text then is the step's own error (a full runtime tmpfs, a
    // directory that exists, a permission fault).
    Process {
        id: files
        property var completion: null
        stderr: StdioCollector { id: filesErrors }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            const error = done === null ? "" : filesErrors.text.trim();
            root.stepDone(done !== null && done.code === 0,
                (done === null ? "start=failed" : "status=" + done.code) + (error === "" ? "" : " stderr=" + JSON.stringify(error)));
        }
    }
}
