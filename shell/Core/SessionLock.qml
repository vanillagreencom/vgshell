import QtQuick
import Quickshell
import qs.Commons

// Owns the requested lock and its content. The content belongs to one plugin
// instance; the lock itself survives that instance until explicitly unlocked.
Scope {
    id: root
    property bool lockRequested: false
    property var lockContent: null
    property bool lockSecure: false
    property var lockContentOwner: null
    // REVISIT(D113): Recovery across shell failure needs an independent owner.
    // This record and its timer survive the plugin, not the whole shell.
    property var release: null
    // How many requested locks the compositor refused or ended while the
    // holder still asked for them, bindable, so the holder sees each one.
    property int compositorEnds: 0
    // Hyprland readings in a row that found the session unlocked while
    // this lock is confirmed (compositorReading).
    property int unlockedReadings: 0

    // REVISIT(D056): A session observer needs a lock not owned by this shell.
    // Report locked from the request until the compositor releases it.
    function sessionProvider(ctx) {
        return Object.freeze({
            get locked() { return root.lockRequested || root.lockSecure; },
            get displaysOff() { return Compositor.displaysOff; }
        });
    }

    function provider(ctx) {
        let disposed = false;
        ctx.onDispose(() => { disposed = true; root.dropLock(ctx); });
        const live = () => !disposed && ctx.active;
        return {
            lock: content => live() ? root.lock(ctx, content) : "refused: lock=released",
            unlock: () => !live() ? "refused: lock=released" : root.lockContentOwner !== ctx ? "refused: lock=not-owner" : root.unlock(),
            unlockFor: milliseconds => live() ? root.unlockFor(ctx, milliseconds) : "refused: lock=released",
            get locked() { return root.lockRequested; },
            get temporary() { return root.release !== null; },
            get hasContent() { return root.lockContent !== null; },
            get secure() { return root.lockSecure; },
            get compositorEnds() { return root.compositorEnds; }
        };
    }

    // lock: the one session lock, drawn by LockHost. `content` is a
    // Component the holder owns; LockHost builds it once per screen and
    // assigns its `screen`.
    function lock(ctx, content) {
        if (content === null || content === undefined || typeof content.createObject !== "function")
            return "refused: lock-content=not-a-component";
        endRelease("lock-request");
        lockContentOwner = ctx;
        lockContent = content;
        lockRequested = true;
        return "ok";
    }

    function unlock() {
        if (release !== null) return "refused: lock=busy";
        lockRequested = false;
        return "ok";
    }

    // The exclusive lock holder supplies milliseconds; its service owns
    // the user-facing duration policy. Qt Timer's interval is a signed int:
    // https://doc.qt.io/qt-6/qml-qtqml-timer.html#interval-prop
    function unlockFor(ctx, milliseconds) {
        if (!Number.isInteger(milliseconds) || milliseconds <= 0 || milliseconds > 2147483647)
            return "refused: lock-duration=integer-1..2147483647";
        if (release !== null) return "refused: lock=busy";
        if (!lockRequested || !lockSecure) return "refused: lock=not-secure";
        if (lockContentOwner !== ctx || lockContent === null) return "refused: lock=not-owner";
        release = { owner: ctx, milliseconds: milliseconds };
        releaseClock.restart();
        releaseTimer.interval = milliseconds;
        releaseTimer.start();
        lockRequested = false;
        return "ok";
    }

    function endRelease(reason) {
        if (release === null) return;
        releaseTimer.stop();
        release = null;
        console.info("capabilities: lock-release=ended reason=" + reason + " relock=requested");
    }

    function expireTemporary() {
        if (release === null) return;
        const remaining = release.milliseconds - releaseClock.elapsedMs();
        // A queued callback from an earlier release cannot shorten this one.
        if (remaining > 0) {
            releaseTimer.interval = remaining;
            releaseTimer.start();
            return;
        }
        endRelease("timeout");
        lockRequested = true;
    }

    // QS 0.3.1 ElapsedTimer measures from restart() using QElapsedTimer:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/ElapsedTimer/
    // Qt's steady clock excludes wall-clock edits; Timer needs a responsive
    // event loop, and Linux suspend can extend this running-time window.
    ElapsedTimer { id: releaseClock }
    Timer {
        id: releaseTimer
        repeat: false
        onTriggered: root.expireTemporary()
    }

    // The compositor ended a lock the holder still requests. REASON is
    // `finished` when it refused or ended it, as Hyprland does while another
    // client holds the session with misc:allow_session_lock_restore off:
    // Quickshell 0.3.1 then drops the lock itself
    // (`ext_session_lock_v1_finished` unlocks, and `WlSessionLock::unlock`
    // clears its target). It is `unlocked-elsewhere` when compositorReading
    // found the session unlocked under a confirmed lock. The request is
    // dropped with it: the session reads unlocked, for the holder and for
    // `session` readers alike, and the next request locks again. LockHost
    // calls it; a release the holder asked for finds no request and does
    // nothing.
    function compositorEnded(reason) {
        if (!lockRequested) return;
        lockRequested = false;
        lockSecure = false;
        unlockedReadings = 0;
        compositorEnds += 1;
        console.warn("capabilities: lock=ended-by-compositor reason=" + reason + "; another client holds or released the session lock, and this shell's lock is dropped");
    }

    // One reading of Hyprland's session lock, `hyprctl -j monitors` TEXT,
    // which LockHost takes every two seconds while this lock is confirmed.
    // Hyprland 0.56.2 with misc:allow_session_lock_restore on, which the
    // VGS layer sets, lets another client's lock replace this one and sends
    // this one nothing; that client's unlock then unlocks the session
    // (`CSessionLockManager::onNewSessionLock`, `CSessionLock`'s
    // unlock_and_destroy). Two readings in a row that SessionLockState
    // reads as unlocked end the lock as the compositor's; any other
    // reading starts the count again.
    function compositorReading(text) {
        const unlocked = lockSecure && SessionLockState.read(text) === "unlocked";
        unlockedReadings = unlocked ? unlockedReadings + 1 : 0;
        if (unlockedReadings >= 2) compositorEnded("unlocked-elsewhere");
    }

    // A lock request the compositor has not confirmed by the time this
    // timer fires leaves the session unlocked while the holder asked for a
    // lock; the log says so.
    Timer {
        interval: 5000
        running: root.lockRequested && !root.lockSecure
        onTriggered: console.error("capabilities: lock requested but the compositor has not confirmed it")
    }

    // An instance of the holder is gone. The content it handed over goes
    // with it, but a locked session stays locked: unloading the lock screen
    // never unlocks the desktop.
    function dropLock(ctx) {
        if (release !== null && release.owner === ctx) {
            endRelease("owner-disposed");
            lockRequested = true;
        }
        if (lockContentOwner !== ctx) return;
        lockContentOwner = null;
        lockContent = null;
    }

}
