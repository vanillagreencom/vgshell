import QtQuick
import QtTest
import Quickshell.Io
import qs.Core

Item {
    id: root
    // The lock route's two collaborators: the idle registry, whose live
    // lock-stage ticket is `liveTicket` for acme.lock, and the cover owner,
    // which records each request it is told of.
    QtObject {
        id: idleStub
        property var liveTicket: null
        function ticketFor(owner, stage, token) {
            return owner === "acme.lock" && stage === "lock" && token !== null && token === liveTicket ? { token: token } : null;
        }
    }
    QtObject {
        id: coversStub
        property var told: []
        function lockRequested(cause, wasLocked) { told = told.concat([[cause, wasLocked]]); }
    }
    Component { id: ownerComponent; SessionLock { idle: idleStub; covers: coversStub } }
    Component {
        id: readerComponent
        QtObject {
            property var session: null
            readonly property bool locked: session !== null && session.locked
        }
    }
    Component { id: contentComponent; Item { property var screen: null } }

    TestCase {
        name: "session-lock"
        property var owner: null
        property var reader: null

        function init() {
            idleStub.liveTicket = null;
            coversStub.told = [];
            owner = createTemporaryObject(ownerComponent, root);
            reader = createTemporaryObject(readerComponent, root);
            verify(owner !== null && reader !== null);
            reader.session = owner.sessionProvider({});
        }

        function test_live_state_data() {
            return [
                { tag: "unlocked", requested: false, secure: false, locked: false },
                { tag: "request-pending", requested: true, secure: false, locked: true },
                { tag: "confirmed", requested: true, secure: true, locked: true },
                { tag: "release-pending", requested: false, secure: true, locked: true }
            ];
        }

        function test_live_state(data) {
            owner.lockRequested = data.requested;
            owner.lockSecure = data.secure;
            tryCompare(reader, "locked", data.locked, 100);
            // Reuse the same reader after release, not a fresh provider.
            owner.lockRequested = false;
            owner.lockSecure = false;
            tryCompare(reader, "locked", false, 100);
        }

        function test_read_only_data() {
            return [
                { tag: "assign", change: s => { s.locked = true; } },
                { tag: "redefine", change: s => Object.defineProperty(s, "locked", { value: true }) },
                { tag: "delete", change: s => { delete s.locked; } },
                { tag: "add-authority", change: s => { s.unlock = () => "planted"; } }
            ];
        }

        function test_read_only(data) {
            const session = reader.session;
            try { data.change(session); } catch (e) {}
            verify(Object.isFrozen(session));
            compare(Object.keys(session).sort().join(","), "displaysOff,locked");
            compare(session.lock, undefined);
            compare(session.unlock, undefined);
            compare(session.locked, false);
            owner.lockRequested = true;
            tryCompare(reader, "locked", true, 100);
        }

        // expected-log: capabilities: lock=ended-by-compositor reason=finished -- the compositor refuses the requested lock
        function test_compositor_end_drops_the_request() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            tryCompare(reader, "locked", true);
            owner.compositorEnded("finished");
            compare(owner.lockRequested, false);
            compare(holder.locked, false);
            compare(holder.secure, false);
            compare(holder.compositorEnds, 1);
            tryCompare(reader, "locked", false);
            // The next request locks again.
            compare(holder.lock(contentComponent, manual), "ok");
            compare(holder.locked, true);
        }

        function test_a_released_lock_is_no_compositor_end() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            compare(holder.unlock(), "ok");
            owner.compositorEnded("finished");
            compare(holder.compositorEnds, 0);
            compare(holder.locked, false);
        }

        readonly property var manual: ({ cause: "manual" })

        function holderOf(id) {
            return owner.provider({ id: id, active: true, onDispose: fn => {} });
        }

        function test_request_causes_data() {
            return [
                { tag: "manual", request: { cause: "manual" } },
                { tag: "sleep", request: { cause: "sleep" } },
                { tag: "restore", request: { cause: "restore" } },
                { tag: "release-end", request: { cause: "release-end" } }
            ];
        }

        function test_request_causes(data) {
            const holder = holderOf("acme.lock");
            compare(holder.lock(contentComponent, data.request), "ok");
            compare(owner.lockCause, data.request.cause);
            compare(coversStub.told, [[data.request.cause, false]]);
        }

        function test_refused_requests_data() {
            return [
                { tag: "no request", request: undefined, reply: "refused: lock-request=undefined want=object" },
                { tag: "unknown cause", request: { cause: "later" }, reply: 'refused: lock-cause="later" want=idle|manual|sleep|restore|release-end' },
                { tag: "idle without a ticket", request: { cause: "idle" }, reply: "refused: lock-request=cause want=cause,ticket" },
                { tag: "idle with a ticket the core never minted", request: { cause: "idle", ticket: {} }, reply: "refused: lock-ticket=stale" }
            ];
        }

        function test_refused_requests(data) {
            const holder = holderOf("acme.lock");
            compare(holder.lock(contentComponent, data.request), data.reply);
            compare(owner.lockRequested, false);
            compare(owner.lockContent, null);
            compare(coversStub.told, []);
        }

        function test_idle_lock_takes_the_live_ticket() {
            const ticket = Object.freeze({});
            idleStub.liveTicket = ticket;
            compare(holderOf("acme.other").lock(contentComponent, { cause: "idle", ticket: ticket }), "refused: lock-ticket=stale");
            compare(holderOf("acme.lock").lock(contentComponent, { cause: "idle", ticket: ticket }), "ok");
            compare(owner.lockCause, "idle");
            compare(coversStub.told, [["idle", false]]);
        }

        function test_a_later_request_keeps_the_first_cause() {
            const ticket = Object.freeze({});
            idleStub.liveTicket = ticket;
            const holder = holderOf("acme.lock");
            compare(holder.lock(contentComponent, { cause: "manual" }), "ok");
            compare(holder.lock(contentComponent, { cause: "idle", ticket: ticket }), "ok");
            compare(owner.lockCause, "manual");
            compare(coversStub.told, [["manual", false], ["idle", true]]);
            compare(holder.unlock(), "ok");
            compare(owner.lockCause, "");
        }

        function monitors(...reasons) {
            return JSON.stringify(reasons.map((r, i) => ({ name: "DP-" + i, solitaryBlockedBy: r })));
        }

        // expected-log: capabilities: lock=ended-by-compositor reason=unlocked-elsewhere -- another client released the session under the confirmed lock
        function test_two_unlocked_readings_end_a_confirmed_lock() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            owner.compositorReading(monitors(["WINDOWED"]));
            compare(holder.locked, true, "one reading is not enough");
            owner.compositorReading(monitors(["WINDOWED", "CANDIDATE"], []));
            compare(holder.locked, false);
            compare(holder.secure, false);
            compare(holder.compositorEnds, 1);
            tryCompare(reader, "locked", false);
        }

        function test_readings_that_do_not_show_an_unlocked_session_keep_the_lock_data() {
            return [
                { tag: "LOCK named", between: monitors(["WINDOWED", "LOCK"]) },
                { tag: "LOCK on the second monitor", between: monitors(["WINDOWED"], ["LOCK"]) },
                { tag: "only a monitor with no workspace", between: monitors(["WORKSPACE"]) },
                { tag: "no monitor", between: "[]" },
                { tag: "unreadable", between: "" },
                { tag: "not JSON", between: "hyprctl: no instance" }
            ];
        }

        function test_readings_that_do_not_show_an_unlocked_session_keep_the_lock(data) {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            // An unlocked reading, then this one, then an unlocked one: the
            // count starts again, so the lock stays.
            owner.compositorReading(monitors(["WINDOWED"]));
            owner.compositorReading(data.between);
            owner.compositorReading(monitors(["WINDOWED"]));
            compare(holder.locked, true);
            compare(holder.compositorEnds, 0);
        }

        function test_an_unconfirmed_lock_is_not_read() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            for (let i = 0; i < 3; i++) owner.compositorReading(monitors(["WINDOWED"]));
            compare(holder.locked, true);
            compare(holder.compositorEnds, 0);
        }

        function test_holder_unload_keeps_lock() {
            let dispose = null;
            const holder = owner.provider({ active: true, onDispose: fn => { dispose = fn; } });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            tryCompare(reader, "locked", true);
            verify(dispose !== null);
            dispose();
            compare(owner.lockContent, null);
            compare(owner.lockRequested, true);
            compare(holder.locked, true);
            compare(reader.session.locked, true);
            compare(holder.unlock(), "refused: lock=released");
            compare(reader.session.locked, true);
        }

        function test_temporary_expiry_relocks() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            compare(holder.unlockFor(160), "ok");
            compare(holder.temporary, true);
            compare(holder.locked, false);
            // The same provider and content survive the release. The real
            // core Timer, not a copied release model, requests the relock.
            tryCompare(owner, "lockRequested", true, 2000);
            compare(holder.temporary, false);
            compare(owner.lockContent, contentComponent);
        }

        function test_temporary_refusals_do_not_renew() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            compare(holder.unlockFor(160), "refused: lock=not-secure");
            owner.lockSecure = true;
            for (const value of [0, -1, 1.5, Infinity, NaN, "160", 2147483648])
                compare(holder.unlockFor(value), "refused: lock-duration=integer-1..2147483647");
            compare(holder.unlockFor(160), "ok");
            const original = owner.release;
            compare(holder.unlockFor(2000), "refused: lock=busy");
            compare(holder.unlock(), "refused: lock=busy");
            compare(owner.release, original);
            tryCompare(owner, "lockRequested", true, 1500);
            compare(holder.temporary, false);
        }

        function test_normal_lock_cancels_temporary_and_stale_callback_cannot_end_next() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            compare(holder.unlockFor(1000), "ok");
            compare(holder.lock(contentComponent, manual), "ok");
            compare(holder.temporary, false);
            compare(holder.locked, true);
            compare(holder.unlockFor(1000), "ok");
            const current = owner.release;
            owner.expireTemporary();
            compare(owner.release, current);
            compare(holder.locked, false);
            compare(holder.lock(contentComponent, manual), "ok");
        }

        // The core's own relocks that end a temporary release take cause
        // release-end, so the cover presentation dismisses a running cover
        // and the lock screen shows (PluginLogic.coverOnLock).
        function test_core_relocks_end_a_release_data() {
            return [{ tag: "expiry" }, { tag: "owner-disposal" }];
        }

        function test_core_relocks_end_a_release(data) {
            let dispose = null;
            const holder = owner.provider({ active: true, onDispose: fn => { dispose = fn; } });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            compare(holder.unlockFor(data.tag === "expiry" ? 120 : 60000), "ok");
            compare(owner.lockCause, "");
            owner.lockSecure = false;
            coversStub.told = [];
            if (data.tag === "expiry") tryCompare(owner, "lockRequested", true, 2000);
            else dispose();
            compare(owner.lockRequested, true);
            compare(owner.lockCause, "release-end");
            compare(coversStub.told, [["release-end", false]]);
        }

        function test_disposal_relocks_before_content_drops_and_stale_owner_cannot_mutate() {
            let disposeOld = null, disposeCurrent = null;
            const old = owner.provider({ active: true, onDispose: fn => { disposeOld = fn; } });
            const holder = owner.provider({ active: true, onDispose: fn => { disposeCurrent = fn; } });
            compare(old.lock(contentComponent, manual), "ok");
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            compare(old.unlockFor(1000), "refused: lock=not-owner");
            compare(old.unlock(), "refused: lock=not-owner");
            compare(holder.unlockFor(1000), "ok");
            const current = owner.release;
            disposeOld();
            compare(owner.release, current);
            compare(old.lock(contentComponent, manual), "refused: lock=released");
            compare(old.unlockFor(1000), "refused: lock=released");
            let lockedAtRemoval = null;
            const removed = () => { if (owner.lockContent === null) lockedAtRemoval = owner.lockRequested; };
            owner.lockContentChanged.connect(removed);
            disposeCurrent();
            owner.lockContentChanged.disconnect(removed);
            compare(lockedAtRemoval, true);
            compare(holder.locked, true);
            compare(holder.temporary, false);
            compare(holder.unlock(), "refused: lock=released");
        }

        function markerFile() {
            for (const child of owner.data) if (child.path === owner.releaseMarkerPath) return child;
            fail("no release marker view");
        }

        function markerRemoval() {
            const command = "rm -f -- " + owner.releaseMarkerPath;
            return ProcessRegistry.processes.find(p => p.running && p.command.join(" ") === command);
        }

        // The marker is on the disk before the unlock is asked for, and
        // goes only once the relock is confirmed.
        function test_release_marks_before_unlock_and_clears_after_secure_relock() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            const file = markerFile();
            let markedAtUnlock = null;
            const seen = () => { if (!owner.lockRequested) markedAtUnlock = file.written; };
            owner.lockRequestedChanged.connect(seen);
            compare(holder.unlockFor(160), "ok");
            owner.lockRequestedChanged.disconnect(seen);
            verify(markedAtUnlock !== null && markedAtUnlock !== "");
            verify(Number.isFinite(JSON.parse(markedAtUnlock).expiresAt));
            compare(owner.releaseMarked, true);
            owner.lockSecure = false;
            tryCompare(owner, "lockRequested", true, 2000);
            compare(markerRemoval(), undefined);
            owner.lockSecure = true;
            const removal = markerRemoval();
            verify(removal !== undefined);
            // A release asked for while the removal runs would lose its
            // marker to it.
            compare(holder.unlockFor(160), "refused: lock=busy");
            removal.finish(0, 0);
            compare(owner.releaseMarked, false);
            compare(holder.unlockFor(160), "ok");
            compare(holder.lock(contentComponent, manual), "ok");
        }

        // expected-log: capabilities: lock-release-marker=unwritten -- the planted write failure
        function test_unwritten_marker_refuses_release() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            markerFile().failNextWrite = FileViewError.PermissionDenied;
            compare(holder.unlockFor(160), "refused: lock=marker-unwritten");
            compare(owner.lockRequested, true);
            compare(holder.temporary, false);
            compare(owner.releaseMarked, false);
        }

        // expected-log: capabilities: lock-release-marker=unwritten cause=readback -- the planted lost write
        function test_lost_marker_write_refuses_release() {
            const holder = owner.provider({ active: true, onDispose: fn => {} });
            compare(holder.lock(contentComponent, manual), "ok");
            owner.lockSecure = true;
            // Reported saved, never on the disk: the read-back finds none.
            markerFile().loseNextWrite = true;
            compare(holder.unlockFor(160), "refused: lock=marker-unwritten");
            compare(owner.lockRequested, true);
            compare(holder.temporary, false);
            compare(owner.releaseMarked, false);
        }

        function test_start_marker_locks_data() {
            return [
                { tag: "none", content: "", locks: false },
                { tag: "live", content: JSON.stringify({ pid: 4242, expiresAt: Date.now() + 60000, mark: 1 }) + "\n", locks: true },
                { tag: "stale", content: JSON.stringify({ pid: 1, expiresAt: 0, mark: 9 }) + "\n", locks: true },
                { tag: "unparsed", content: "x", locks: true }
            ];
        }

        // expected-log: capabilities: lock-release=recovered -- each planted marker the start reads
        function test_start_marker_locks(data) {
            markerFile().content = data.content;
            owner.recoverRelease();
            compare(owner.lockRequested, data.locks);
            compare(owner.releaseMarked, data.locks);
            // A recovered release shows the lock screen, as every relock
            // that ends a release does.
            compare(owner.lockCause, data.locks ? "release-end" : "");
            compare(coversStub.told, data.locks ? [["release-end", false]] : []);
        }
    }
}
