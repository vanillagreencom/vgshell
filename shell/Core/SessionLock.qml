import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "PluginLogic.js" as Logic

// Owns the requested lock and its content. The content belongs to one plugin
// instance; the lock itself survives that instance until explicitly unlocked.
Scope {
    id: root
    required property var idle
    required property var covers
    property bool lockRequested: false
    // The cause of the request that took the session, one of
    // PluginLogic.LOCK_CAUSES, or "" while unlocked.
    property string lockCause: ""
    property var lockContent: null
    property bool lockSecure: false
    property var lockContentOwner: null
    // This record and its timer survive the plugin, not the shell; the
    // release marker carries the release across a shell that stops.
    property var release: null
    // The release marker: written before a temporary release unlocks and
    // removed once the relock is secure, so the next shell's start locks
    // again after any stop during a release, a restart or a crash (D114).
    // XDG_RUNTIME_DIR is per user and lasts while any session of the user
    // or lingering keeps it, so a marker left at logout locks the next
    // login's first shell, which is safe.
    readonly property string releaseMarkerPath: Quickshell.env("XDG_RUNTIME_DIR") + "/vgshell/lock-release"
    // Whether a marker this shell wrote or found waits for its removal.
    property bool releaseMarked: false
    // Makes every marker's bytes differ: FileView skips a write of the
    // bytes it last read or wrote and reports nothing (WatchedFile).
    property int releaseMarks: 0
    property bool releaseMarkSaved: false
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
            lock: (content, request) => live() ? root.lock(ctx, content, request) : "refused: lock=released",
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
    // assigns its `screen`. `request` names its cause
    // (PluginLogic.lockRequestRefusal); an idle request carries the ticket
    // the holder's own lock stage watch handed it, checked here, so only an
    // idle event the core saw can bring the cover into the lock. The lock
    // is taken before the cover is placed, and never waits for it.
    function lock(ctx, content, request) {
        if (content === null || content === undefined || typeof content.createObject !== "function")
            return "refused: lock-content=not-a-component";
        const refusal = Logic.lockRequestRefusal(request);
        if (refusal !== "") return refusal;
        if (request.cause === "idle" && idle.ticketFor(ctx.id, "lock", request.ticket) === null)
            return "refused: lock-ticket=stale";
        lockContentOwner = ctx;
        lockContent = content;
        relock(request.cause, "lock-request");
        return "ok";
    }

    // Take the session for CAUSE. Every lock comes here: a holder's request
    // and the core's own relocks that end a temporary release, which take
    // `release-end`. Any release still running ends first, named REASON,
    // and the cover presentation hears of each lock the session takes.
    function relock(cause, reason) {
        const wasLocked = lockRequested || lockSecure;
        endRelease(reason);
        lockRequested = true;
        if (!wasLocked) lockCause = cause;
        covers.lockRequested(cause, wasLocked);
    }

    function unlock() {
        if (release !== null) return "refused: lock=busy";
        lockRequested = false;
        lockCause = "";
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
        // A removal still running would delete the marker written now.
        if (releaseMarkerRemove.running) return "refused: lock=busy";
        if (!markRelease(milliseconds)) return "refused: lock=marker-unwritten";
        release = { owner: ctx, milliseconds: milliseconds };
        releaseClock.restart();
        releaseTimer.interval = milliseconds;
        releaseTimer.start();
        lockRequested = false;
        lockCause = "";
        return "ok";
    }

    // Write the release marker before any unlock; true only once the file
    // read back holds the line just written. blockWrites reports `saved` or
    // `saveFailed` before setText returns, but `saved` proves no landing:
    // FileViewWriter::write only warns when the atomic commit fails, as on
    // a full runtime tmpfs, and the view still reports `saved` with the
    // bytes in hand. blockAllReads makes text() after reload() wait for a
    // fresh read of the file (Quickshell 0.3.1 src/io/fileview.cpp:
    // FileViewWriter::write, FileView::reload, shouldBlockRead, loadSync).
    function markRelease(milliseconds) {
        releaseMarks += 1;
        releaseMarkSaved = false;
        const line = JSON.stringify({ pid: Quickshell.processId, expiresAt: Date.now() + milliseconds, mark: releaseMarks }) + "\n";
        releaseMarker.setText(line);
        if (!releaseMarkSaved) return false;
        releaseMarker.reload();
        if (releaseMarker.text() !== line) {
            console.error("capabilities: lock-release-marker=unwritten cause=readback path=" + releaseMarkerPath);
            return false;
        }
        releaseMarked = true;
        return true;
    }

    // At the guarded shell's start: a marker means the shell before stopped
    // during a temporary release, or before its relock was confirmed, and
    // the desktop may be open with no expiry left. Lock at once; the lock
    // holder hands its screen over when it is built. Locking is always
    // safe, so a marker of any age or pid locks. blockAllReads makes text()
    // wait for the read; the reference allows a blocking read before the
    // first window (Quickshell 0.3.1 FileView, src/io/fileview.hpp); a
    // missing file reads as "".
    function recoverRelease() {
        if (releaseMarker.text() === "") return;
        releaseMarked = true;
        console.warn("capabilities: lock-release=recovered marker=" + releaseMarkerPath + " relock=requested");
        relock("release-end", "recovered");
    }

    onLockSecureChanged: {
        if (lockSecure && lockRequested && release === null && releaseMarked && !releaseMarkerRemove.running)
            releaseMarkerRemove.running = true;
    }

    FileView {
        id: releaseMarker
        path: root.releaseMarkerPath
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: root.releaseMarkSaved = true
        onSaveFailed: error => console.error("capabilities: lock-release-marker=unwritten cause=save-failed path=" + root.releaseMarkerPath + " error=" + error)
    }

    // A removal that fails keeps the marker, so the next start locks again.
    Process {
        id: releaseMarkerRemove
        property var completion: null
        command: ["rm", "-f", "--", root.releaseMarkerPath]
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done !== null && done.code === 0) {
                root.releaseMarked = false;
                return;
            }
            console.error("capabilities: lock-release-marker=kept path=" + root.releaseMarkerPath + (done === null ? " start=failed" : " status=" + done.code));
        }
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
        relock("release-end", "timeout");
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
        lockCause = "";
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
        if (release !== null && release.owner === ctx) relock("release-end", "owner-disposed");
        if (lockContentOwner !== ctx) return;
        lockContentOwner = null;
        lockContent = null;
    }

}
