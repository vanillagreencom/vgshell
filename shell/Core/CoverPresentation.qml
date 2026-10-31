import QtQuick
import Quickshell
import "PluginLogic.js" as Logic

// The one cover presentation: whether the screensaver stage owner's cover
// shows, and where. `none` shows nothing, `desktop` draws it on the
// ordinary cover layer, and `secure` holds it inside the lock surface over
// a lock the core already holds. Each screen's CoverHost owns that screen's
// one cover instance and moves it between the two placements; LockHost
// registers each lock surface's root here and dismisses the cover on the
// first input. The owner's service asks through capability `cover` and
// reads `running` from it; no plugin can lock or unlock through it.
//
// A presentation ends on the first input under the lock, on a stop or a
// failure the owner reports, a manual, sleep or restore lock, an unlock,
// the panels going off, the owner changing, being rebuilt or going, and
// its last cover instance going. A new one starts only from a manual
// start, a valid idle ticket of the owner's screensaver stage or Lock's own
// idle event (coverStartsWithLock), and only while a cover instance of the
// owner exists, so nothing that ended can map again and a cover whose
// build failed or was refused (a restart owed) never holds the lock's
// screen in front of the lock content.
Scope {
    id: root

    required property var idle
    required property var sessionLock

    readonly property string ownerId: Logic.coverOwner(idle.stageRecord.stages, Registry.manifests)
    // The owner's source revision: a rebuilt owner ends the presentation
    // its old instances drew.
    readonly property var ownerRevision: Logic.hasOwn(Registry.manifests, ownerId) ? Registry.manifests[ownerId].__revision : null
    // { placement, generation, origin }, replaced whole: `generation`
    // counts the presentations started, and `origin` is what started the
    // running one, `manual`, `idle` (the owner's stage watch) or `lock`
    // (Lock's idle event at an equal time).
    property var state: ({ placement: "none", generation: 0, origin: "" })
    readonly property string placement: state.placement
    // Why the last presentation ended, for the lending record.
    property string ended: ""
    // One { name, item } per lock surface that offers a place for the
    // cover, in the order offered; each surface takes back only its own.
    property var secureEntries: []
    // Screen name -> the item LockHost made inside that screen's lock
    // surface for the cover, the latest a surface of that screen offered.
    readonly property var secureRoots: {
        const out = {};
        for (const entry of secureEntries) out[entry.name] = entry.item;
        return out;
    }
    readonly property bool sessionLocked: sessionLock.lockRequested || sessionLock.lockSecure
    // One entry per screen whose CoverHost holds a built cover instance of
    // the owner; each host takes back only its own.
    property var builtEntries: []
    readonly property bool built: builtEntries.length > 0
    onBuiltChanged: if (!built) dismiss("unbuilt")

    onOwnerIdChanged: dismiss("owner")
    onOwnerRevisionChanged: dismiss("owner")
    // A cover behind dark panels would keep a renderer busy for as long as
    // the user is away; Lock shows when they wake.
    readonly property bool displaysOff: Compositor.displaysOff
    onDisplaysOffChanged: if (displaysOff) dismiss("displays-off")
    readonly property bool lockHeld: sessionLock.lockRequested
    onLockHeldChanged: if (!lockHeld && placement === "secure") dismiss("unlocked")

    // cover: the owner's service starts and ends its desktop presentation.
    // `present()` is a manual start and `present(ticket)` an idle one, the
    // ticket its screensaver stage watch handed it; `stop()` ends a desktop
    // presentation, which the first input ends under the lock; `failed()`
    // ends either when the cover cannot draw. `running` and `placement`
    // read the presentation.
    function provider(ctx) {
        ctx.onDispose(() => { if (root.ownerId === ctx.id) root.dismiss("released"); });
        return Object.freeze({
            present: ticket => root.present(ctx, ticket),
            stop: () => root.stop(ctx),
            failed: () => root.failed(ctx),
            get running() { return root.ownerId === ctx.id && root.state.placement !== "none"; },
            get placement() { return root.ownerId === ctx.id ? root.state.placement : "none"; }
        });
    }

    // What the core hands each cover instance as `presentation`: whether
    // the presentation runs and where it sits, read-only and bindable. The
    // instance draws and runs its renderer while `active`.
    function contextFor() {
        return Object.freeze({
            get active() { return root.state.placement !== "none"; },
            get placement() { return root.state.placement; }
        });
    }

    function present(ctx, ticket) {
        const ticketState = ticket === undefined ? "none" : root.idle.ticketFor(ctx.id, "screensaver", ticket) !== null ? "valid" : "stale";
        const result = Logic.coverPresentAnswer({ caller: ctx.id, owner: ownerId, ticket: ticketState, built: built, displaysOff: displaysOff, locked: sessionLocked, placement: placement });
        if (result.start) begin("desktop", ticketState === "valid" ? "idle" : "manual");
        return result.answer;
    }

    function stop(ctx) {
        if (ctx.id !== ownerId) return "refused: cover=not-owner";
        // Under the lock only the barrier's first input ends the cover, so
        // the input that ends it never reaches the lock content.
        if (placement === "secure") return "refused: cover=secure";
        dismiss("stopped");
        return "ok";
    }

    function failed(ctx) {
        if (ctx.id !== ownerId) return "refused: cover=not-owner";
        dismiss("failed");
        return "ok";
    }

    // SessionLock's call for each lock request it took, after it holds
    // the lock: the cause, and whether the session was already locked.
    function lockRequested(cause, wasLocked) {
        const starts = Logic.coverStartsWithLock(root.idle.currentStages(), ownerId);
        const action = Logic.coverOnLock(cause, wasLocked, placement, starts, displaysOff, built);
        if (action === "transfer") state = { placement: "secure", generation: state.generation, origin: state.origin };
        else if (action === "start") begin("secure", "lock");
        else if (action === "dismiss") dismiss("superseded");
    }

    // LockHost's barrier took the first input under the lock.
    function dismissByInput() {
        dismiss("input");
    }

    function begin(where, origin) {
        ended = "";
        state = { placement: where, generation: state.generation + 1, origin: origin };
    }

    function dismiss(reason) {
        if (state.placement === "none") return;
        ended = reason;
        state = { placement: "none", generation: state.generation, origin: "" };
    }

    // A CoverHost holds a built cover instance of the owner; returns the
    // disposer the host calls when that instance goes.
    function registerBuilt() {
        const entry = {};
        builtEntries = builtEntries.concat([entry]);
        return () => { root.builtEntries = root.builtEntries.filter(other => other !== entry); };
    }

    // LockHost's lock surface on SCREEN offers ITEM as the cover's place;
    // returns the disposer the surface calls as it goes.
    function registerSecureRoot(screen, item) {
        const entry = { name: screen.name, item: item };
        secureEntries = secureEntries.concat([entry]);
        return () => { root.secureEntries = root.secureEntries.filter(other => other !== entry); };
    }

    // The lending record: the owner, the presentation, why the last one
    // ended, and for each lock surface the plugins whose cover sits in it.
    function record() {
        const secure = {};
        for (const name of Object.keys(secureRoots).sort())
            secure[name] = Array.from(secureRoots[name].children).filter(child => typeof child.pluginId === "string").map(child => child.pluginId);
        return { owner: ownerId, built: builtEntries.length, placement: state.placement, generation: state.generation, origin: state.origin, ended: ended, secure: secure };
    }
}
