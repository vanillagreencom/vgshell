import QtQuick
import Quickshell
import Quickshell.Hyprland
import "PluginLogic.js" as Logic
import "HyprlandLayer.js" as Layer

// The one owner of key capture: which control holds the keyboard for a key
// combo, and the Hyprland pass-through submap that lets a combo a bind
// holds reach it (HyprlandLayer.KEY_PASSTHROUGH). A control asks to begin
// and to end, and never dispatches; the owner enters the submap through
// Compositor and leaves it on every end the shell sees: the control's
// commit, cancel or focus loss, the control's destruction, its plugin
// instance's teardown, a newer holder and a bar drag. Hyprland leaves the
// submap by itself on Escape, on the close of the window that entered it,
// on a timeout and when the layer runs again; the window-close leave does
// not apply to a window-free capture. The owner reads each submap change
// from Hyprland's event socket and ends a capture whose submap is gone, so
// the control and Hyprland agree. It also answers who else holds a key,
// with the file and line of each user bind that holds it, and takes such a
// line out of the user's file, or puts it back, for the field that shows
// the conflict.
Scope {
    id: root

    // The control capturing keys, or null. An object property reads null
    // once its object is destroyed, which ends the capture.
    property Item holder: null
    // `idle`; `waiting`, a holder whose enter waits for an earlier leave to
    // run; `entering`, the enter request sent; or `passthrough`, once
    // Hyprland reports the submap current.
    property string phase: "idle"
    // Whether the holder's enter was refused or answered with an error:
    // Hyprland's own binds still run, and only keys they leave reach it.
    property bool failed: false
    // Whether this capture holds no window, for a core caller whose owner
    // releases it because Hyprland has no focused shell window to watch:
    // the layer's `enter` refuses unless the active window is a shell
    // window, and a press on the bar changes no active window.
    property bool anyWindow: false
    // Leave requests sent and not yet answered. A begin while one is
    // pending waits to send its enter until every leave was answered:
    // Hyprland posts a request's submap event before it answers the request
    // (Actions::setSubmap, HyprCtl.cpp), so an earlier capture's events come
    // while the new holder waits, and a waiting holder reads none.
    property int leaving: 0
    // Counts begins, so an enter answer for an earlier capture is dropped.
    property int generation: 0
    property real began: 0
    // The last capture that ended, as { item, reason }: `commit`, `cancel`,
    // `tab`, `focus`, `destroyed`, `disposed`, `superseded`, `compositor`,
    // or `timeout` for a compositor end after the layer's timeout.
    property var ended: ({ item: null, reason: "" })
    // The holder's instance lifetime registration, released when it ends.
    property var release: null
    // HyprlandState, the one reader of `hyprctl -j binds`: its
    // `foreignKeys`, the keys something other than the layer binds, null
    // while unread, its `bindsFailure`, and `readBinds()`. `wantsBinds`
    // keeps its reads on while a control captures or an instance that asked
    // a conflict question lives; it reads again after each Hyprland reload,
    // and a question after a failed read asks once more.
    property var bindsSource: null
    property int askers: 0
    readonly property bool capturing: holder !== null
    readonly property bool wantsBinds: capturing || askers > 0
    // Plain state a conflict question writes while a binding reads it, so
    // the write notifies no binding.
    property var bindsRetry: ({ asked: false })
    readonly property string bindsState: {
        const source = bindsSource;
        return source === null || (source.foreignKeys === null && source.bindsFailure === "") ? "unread" : source.bindsFailure !== "" ? "failed" : "read";
    }
    // QML re-evaluates this binding when the configuration or binds read
    // changes. Its entries belong to that snapshot, not to an opening.
    // https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html
    readonly property var conflictAnswers: {
        const answers = Object.create(null);
        for (const section of Registry.hyprlandSections)
            for (const bind of section.binds)
                answers[conflictId(bind.key, section.id, bind.shortcut)] = conflictAnswer(bind.key, section.id, bind.shortcut);
        return answers;
    }

    function conflictId(key, id, shortcut) {
        return JSON.stringify([Logic.hyprlandKey(key).key, id, shortcut]);
    }
    // The lines removeUserBind took out, by the token it answered, each {
    // file, line, undo } with the undo the edit printed, so an undo puts
    // back only a line the core itself removed. A row goes when its undo
    // succeeds, when the field that holds its token releases it on its
    // destruction, and when the removal answers after its instance was torn
    // down, since no one then holds the token. A later removal or undo in
    // the same file moves the lines after it, and each row's line with
    // them. Plain state: no binding reads it.
    property var removedBinds: ({ next: 1, rows: {} })

    onHolderChanged: if (holder === null && phase !== "idle") finish("destroyed")

    // The `capture` member of the `shortcut` capability for one instance.
    function provider(ctx) {
        const asking = { started: false };
        return {
            get holder() { return root.holder; },
            get passthrough() { return root.phase === "passthrough"; },
            get failed() { return root.failed; },
            get ended() { return root.ended; },
            timeoutMs: Layer.KEY_PASSTHROUGH.timeoutMs,
            begin: item => root.begin(ctx, item),
            end: (item, reason) => root.end(item, reason),
            keyFor: (key, modifiers) => Logic.capturedKey(key, modifiers),
            conflicts: (key, id, shortcut) => {
                if (!asking.started) {
                    asking.started = true;
                    Qt.callLater(() => root.ask(ctx));
                }
                return root.conflicts(key, id, shortcut);
            },
            removeUserBind: (key, done) => root.removeUserBind(key, value => {
                if (ctx.active) done(value);
                else if (value.ok) root.releaseUserBind(value.token);
            }),
            restoreUserBind: (token, done) => root.restoreUserBind(token, value => { if (ctx.active) done(value); }),
            releaseUserBind: token => root.releaseUserBind(token)
        };
    }

    // CTX's instance asked who holds a key: the binds stay read until it is
    // torn down.
    function ask(ctx) {
        if (!ctx.active) return;
        askers += 1;
        ctx.onDispose(() => { root.askers -= 1; });
    }

    // ITEM takes the keyboard for a combo; a holder already capturing ends
    // first. OPTIONS may set anyWindow for core callers. Answers `ok`.
    function begin(ctx, item, options) {
        if (item === null || item === undefined)
            throw new Error("refused: capture holder=none");
        if (holder === item) return "ok";
        if (holder !== null) finish("superseded");
        holder = item;
        release = ctx.onDispose(() => root.end(item, "disposed"));
        failed = false;
        anyWindow = options !== null && options !== undefined && options.anyWindow === true;
        generation += 1;
        began = Date.now();
        if (leaving > 0) phase = "waiting";
        else enter();
        return "ok";
    }

    // ITEM's capture ends for REASON, such as `commit`, `cancel` or
    // `focus`; nothing happens for an item that holds nothing.
    function end(item, reason) {
        if (holder === null || item !== holder) return;
        finish(reason);
    }

    function enter() {
        phase = "entering";
        const at = generation;
        const verb = anyWindow ? "enterAnyWindow" : "enter";
        const answer = Compositor.passthrough(verb, reply => root.entered(at, reply));
        if (answer !== "ok") entered(at, answer);
    }

    function entered(at, reply) {
        if (at !== generation || holder === null || reply === "ok") return;
        failed = true;
        console.info("capture: enter=failed reply=" + JSON.stringify(reply));
    }

    // Every end runs here. The leave request goes out unless Hyprland left
    // the submap itself or no enter was sent: it resets only the
    // pass-through submap, so a leave that follows an enter still in flight
    // undoes it.
    function finish(reason) {
        const was = phase;
        const item = holder;
        const registration = release;
        ended = { item: item, reason: reason };
        phase = "idle";
        release = null;
        failed = false;
        anyWindow = false;
        holder = null;
        if (registration !== null) registration();
        if ((was === "entering" || was === "passthrough") && reason !== "compositor" && reason !== "timeout") leave();
        console.info("capture: end=" + reason);
    }

    function leave() {
        leaving += 1;
        if (Compositor.passthrough("leave", () => root.left()) !== "ok") left();
    }

    function left() {
        leaving -= 1;
        if (leaving === 0 && phase === "waiting") enter();
    }

    function submapChanged(name) {
        if (name === Layer.KEY_PASSTHROUGH.submap) {
            if (phase === "entering") phase = "passthrough";
        } else if (phase === "passthrough") {
            const held = Date.now() - began;
            console.info("capture: compositor submap=" + JSON.stringify(name) + " held_ms=" + held);
            finish(held >= Layer.KEY_PASSTHROUGH.timeoutMs ? "timeout" : "compositor");
        }
    }

    // Who else holds KEY, for the field's hint: Logic.keyConflicts with
    // `binds`, the binds read's state, `unread`, `read` or `failed`, and
    // `hint`, the line Logic.conflictHint writes from them with each plugin
    // named by its manifest, beside it.
    function conflicts(key, id, shortcut) {
        const source = bindsSource;
        const state = bindsState;
        if (state === "failed" && !bindsRetry.asked) {
            bindsRetry.asked = true;
            Qt.callLater(() => source.readBinds());
        } else if (state === "read") {
            bindsRetry.asked = false;
        }
        const identity = conflictId(key, id, shortcut);
        // A newly typed key is not yet in the configuration snapshot.
        const answer = Logic.hasOwn(conflictAnswers, identity) ? conflictAnswers[identity] : conflictAnswer(key, id, shortcut);
        return answer;
    }

    function conflictAnswer(key, id, shortcut) {
        const source = bindsSource;
        const state = bindsState;
        const found = Logic.keyConflicts(key, Registry.hyprlandSections, state === "read" ? source.foreignKeys : [], id, shortcut);
        const names = {};
        for (const p of found.plugins)
            if (Logic.hasOwn(Registry.manifests, p.id)) names[p.id] = Registry.manifests[p.id].name;
        const userBinds = found.user ? source.userBindsFor(Logic.hyprlandKey(key).key) : [];
        const answer = { plugins: found.plugins, user: found.user, binds: state, userBinds: userBinds };
        answer.hint = Logic.conflictHint(answer, names);
        return Object.freeze(answer);
    }

    // Take the one user line that binds KEY, a key a plugin's bind asks
    // for, out of its file, and answer DONE with { ok: true, token, file,
    // line } or { ok: false, error }. The core finds the line itself; the
    // caller names only the key.
    function removeUserBind(key, done) {
        const read = Logic.hyprlandKey(key);
        const asked = read.ok && Registry.hyprlandSections.some(section => section.binds.some(bind => bind.key === read.key));
        const rows = read.ok && bindsSource !== null ? bindsSource.userBindsFor(read.key).filter(row => row.removable) : [];
        if (!asked) { done({ ok: false, error: "refused: user-bind=no-plugin-key key=" + key }); return; }
        if (rows.length !== 1) { done({ ok: false, error: "refused: user-bind=lines count=" + rows.length + " key=" + read.key }); return; }
        const row = rows[0];
        bindsSource.editBinds(["remove-bind", row.file, String(row.line), read.key], value => {
            if (!value.ok) { done(value); return; }
            root.shiftRemoved(row.file, row.line + 1, -1);
            const m = / undo=(\{.*\})$/.exec(value.said);
            if (m === null) { done({ ok: false, error: "refused: user-bind=unread reply=" + JSON.stringify(value.said) }); return; }
            const token = String(removedBinds.next);
            removedBinds.next += 1;
            removedBinds.rows[token] = { file: row.file, line: row.line, undo: JSON.parse(m[1]) };
            done({ ok: true, token: token, file: row.file, line: row.line });
        });
    }

    // Put back the line removeUserBind answered TOKEN for, once; DONE gets
    // { ok: true } or { ok: false, error }.
    function restoreUserBind(token, done) {
        const row = Logic.hasOwn(removedBinds.rows, token) ? removedBinds.rows[token] : null;
        if (row === null || bindsSource === null) { done({ ok: false, error: "refused: user-bind=no-undo token=" + token }); return; }
        bindsSource.editBinds(["restore-bind", row.file, String(row.line), JSON.stringify(row.undo)], value => {
            if (value.ok) {
                root.releaseUserBind(token);
                const m = / line=([0-9]+)$/.exec(value.said);
                root.shiftRemoved(row.file, m === null ? row.line : Number(m[1]), 1);
            }
            done(value.ok ? { ok: true } : value);
        });
    }

    // Forget the line removeUserBind answered TOKEN for, whose undo no one
    // will ask for: nothing is edited and nothing is answered.
    function releaseUserBind(token) {
        delete removedBinds.rows[token];
    }

    // Move by BY the line of each removed row of FILE at line FROM or after:
    // a hint restore-bind reads only where the line's neighbours meet in
    // several places.
    function shiftRemoved(file, from, by) {
        for (const token of Object.keys(removedBinds.rows)) {
            const row = removedBinds.rows[token];
            if (row.file === file && row.line >= from) row.line += by;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submapChanged(event.data);
        }
    }
}
