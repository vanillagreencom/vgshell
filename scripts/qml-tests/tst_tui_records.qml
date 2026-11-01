import QtQuick
import QtTest
import qs.Core
import Quickshell.Io
import Qt.labs.folderlistmodel

Item {
    id: root

    Component {
        id: recordsComponent
        TuiRecords {
            recordDir: "/unit/tui"
            coreBin: "/unit/bin"
        }
    }

    TestCase {
        name: "tui-records"

        property var records: null
        property var model: null
        property var events: []
        readonly property string key: "acme.tui/hello"
        readonly property string run: "1-1"
        readonly property string runningPath: "/unit/tui/acme.tui@hello@1-1.running.json"
        readonly property string endedPath: "/unit/tui/acme.tui@hello@1-1.ended.json"

        function record(state, code) {
            return {
                key: key,
                run: run,
                state: state,
                code: code,
                startedAt: "2026-09-29T07:00:00.000Z",
                endedAt: state === "ended" ? "2026-09-29T07:00:01.000Z" : null,
                window: { appId: "org.vgs.tui", title: "VGS · Hello" }
            };
        }

        function init() {
            ProcessRegistry.clear();
            FolderListRegistry.clear();
            records = createTemporaryObject(recordsComponent, root);
            verify(records !== null, "the record owner builds");
            compare(FolderListRegistry.models.length, 1);
            model = FolderListRegistry.models[0];
            finishReap();
            events = [];
        }

        function finishReap() {
            const reaps = ProcessRegistry.runningWithVerb("reap");
            if (reaps.length === 1) reaps[0].finish(0, 0, "", "");
        }

        function waitProcesses() {
            return ProcessRegistry.runningWithVerb("wait");
        }

        // The listing arms one native read, with no watcher or helper.
        function readerOf(path) {
            verify(Object.prototype.hasOwnProperty.call(records.readers, path), "the record gets a reader: " + path);
            const reader = records.readers[path];
            compare(reader.path, path);
            compare(reader.reads, 1);
            compare(reader.watchers, 0);
            compare(reader.printErrors, false);
            compare(reader.watchChanges, false);
            verify(ProcessRegistry.processes.every(process => ["reap", "wait"].indexOf(process.command[1]) !== -1));
            return reader;
        }

        function finishRead(path, text) {
            const reader = readerOf(path);
            compare(reader.live, "read");
            reader.finishRead(text);
        }

        function listRunning() {
            model.setFiles([runningPath], "reset");
            finishRead(runningPath, JSON.stringify(record("running", null)));
        }

        function failListedRead(error, removed) {
            model.setFiles([runningPath], "reset");
            const reader = readerOf(runningPath);
            // A removed file stays listed until the directory change arrives.
            if (removed) model.setFiles([], "drop");
            reader.failRead(error);
            compare(Object.keys(records.fileRecords), []);
            compare(reader.live, "");
            compare(reader.reads, 1);
        }

        // The engine reports confirmed absence after a listed record is
        // removed before its read completes. The case
        // declares no expected log, so qml-unit.sh fails it on any warning
        // or error line, the failed read's included.
        function test_a_record_removed_during_its_read_logs_nothing() {
            failListedRead(FileViewError.FileNotFound, true);
            model.setFiles([], "remove");
            compare(Object.keys(records.readers), []);
            compare(Object.keys(records.fileRecords), []);
        }

        function test_a_dropped_reader_ending_late_changes_nothing_data() {
            return [
                { tag: "read", ok: true },
                { tag: "failed-read", ok: false }
            ];
        }

        // destroy() defers the delete, so a reader the listing dropped can
        // still end before it goes: its record stays out and nothing logs.
        function test_a_dropped_reader_ending_late_changes_nothing(data) {
            model.setFiles([runningPath], "reset");
            const reader = readerOf(runningPath);
            model.setFiles([], "remove");
            if (data.ok) reader.finishRead(JSON.stringify(record("running", null)));
            else reader.failRead(FileViewError.PermissionDenied);
            compare(Object.keys(records.fileRecords), []);
            wait(0);
            compare(Object.keys(records.readers), []);
            compare(Object.keys(records.fileRecords), []);
        }

        function test_existing_record_read_failure_data() {
            return [
                { tag: "permission-denied", error: FileViewError.PermissionDenied },
                { tag: "not-a-file", error: FileViewError.NotAFile },
                { tag: "present-or-unconfirmed", error: FileViewError.Unknown }
            ];
        }

        // The smoke shell-log check parses the tui: record= error line.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: error=3 -- Permission failures remain errors.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: error=4 -- A path that is not a file remains an error.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: error=1 -- Present or unconfirmed failures remain errors.
        function test_existing_record_read_failure(data) {
            failListedRead(data.error, false);
            compare(Object.keys(records.fileRecords), []);
        }

        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: error=1 -- A missed listing change cannot confirm absence.
        function test_a_listing_removal_does_not_suppress_unconfirmed_failure() {
            failListedRead(FileViewError.Unknown, true);
            compare(Object.keys(records.fileRecords), []);
        }

        function test_a_listed_file_is_read_once_across_listing_changes() {
            listRunning();
            const reader = readerOf(runningPath);
            model.setFiles([runningPath], "reset");
            compare(readerOf(runningPath), reader);
            compare(reader.live, "");
            compare(reader.reloads, 0);
            compare(waitProcesses().length, 1);
        }

        function test_removal_destroys_an_outstanding_reader() {
            model.setFiles([runningPath], "reset");
            const reader = readerOf(runningPath);
            let destroyed = false;
            reader.Component.destruction.connect(() => { destroyed = true; });
            model.setFiles([], "remove");
            wait(0);
            verify(destroyed);
            compare(Object.keys(records.readers), []);
        }

        function addDone() {
            records.addWaiter("core", run, result => events.push(result));
            records.deliverKnown(run);
        }

        function finishWait(code) {
            const waits = waitProcesses();
            compare(waits.length, 1);
            waits[0].finish(0, 0, JSON.stringify(record("ended", code)) + "\n", "");
        }

        function test_wait_covers_a_dropped_folder_change() {
            compare(waitProcesses().length, 0);
            addDone();
            listRunning();
            compare(waitProcesses().length, 1);
            model.setFiles([runningPath, endedPath], "drop");
            finishWait(7);
            compare(JSON.stringify(events), JSON.stringify([{ code: 7, reason: null, package: null }]));
            compare(records.runs.keys[key].running, null);
            compare(records.record().waits, []);
            wait(0);
            compare(JSON.stringify(events), JSON.stringify([{ code: 7, reason: null, package: null }]));
        }

        function test_listing_end_before_wait_calls_done_once() {
            addDone();
            listRunning();
            model.setFiles([runningPath, endedPath], "insert");
            finishRead(endedPath, JSON.stringify(record("ended", 3)));
            compare(JSON.stringify(events), JSON.stringify([{ code: 3, reason: null, package: null }]));
            finishWait(3);
            compare(JSON.stringify(events), JSON.stringify([{ code: 3, reason: null, package: null }]));
            compare(records.record().waits, []);
        }

        function test_no_wait_before_or_after_a_run() {
            compare(waitProcesses().length, 0);
            listRunning();
            compare(waitProcesses().length, 1);
            finishWait(0);
            compare(waitProcesses().length, 0);
            compare(records.record().waits, []);
        }

        function test_dead_run_answers_vanished() {
            addDone();
            listRunning();
            finishWait(null);
            compare(JSON.stringify(events), JSON.stringify([{ code: null, reason: "vanished", package: null }]));
            compare(records.runs.keys[key].running, null);
        }

        function test_launched_run_starts_wait_without_a_listing_data() {
            return [
                { tag: "start-before-end", readFirst: true, listed: false },
                { tag: "listing-catches-up", readFirst: true, listed: true },
                { tag: "end-before-read", readFirst: false, listed: false }
            ];
        }

        function test_launched_run_starts_wait_without_a_listing(data) {
            addDone();
            records.launched(key, run);
            compare(waitProcesses().length, 1);
            const reader = readerOf(runningPath);
            // An unrelated directory update still omits this run's insertion.
            model.setFiles([], "reset");
            compare(readerOf(runningPath), reader);
            if (data.readFirst) {
                finishRead(runningPath, JSON.stringify(record("running", null)));
                compare(records.record().runs[key].running, run);
                compare(JSON.stringify(events), "[]");
                if (data.listed) {
                    model.setFiles([runningPath], "insert");
                    compare(records.readers[runningPath], reader);
                }
            }
            finishWait(9);
            if (!data.readFirst)
                reader.finishRead(JSON.stringify(record("running", null)));
            compare(JSON.stringify(events), JSON.stringify([{ code: 9, reason: null, package: null }]));
            compare(records.runs.keys[key].ended.run, run);
            compare(records.record().runs[key].running, null);
            compare(records.launchedRuns, []);
            model.setFiles([], "remove");
            wait(0);
            compare(Object.keys(records.readers), []);
            compare(Object.keys(records.fileRecords), []);
            compare(JSON.stringify(events), JSON.stringify([{ code: 9, reason: null, package: null }]));
        }

        function test_failed_wait_keeps_the_run_live_until_completion_data() {
            return [
                { tag: "helper-exit", code: 1, status: 0, readFirst: true, listed: false },
                { tag: "failed-start", startFailed: true, readFirst: false, listed: false },
                { tag: "crash", code: 9, status: 1, readFirst: true, listed: true },
                { tag: "missing-result", code: 0, status: 0, readFirst: true, listed: false }
            ];
        }

        // The smoke shell-log check parses these wait outcome categories.
        // expected-log: tui: wait=acme.tui/hello run=1-1 reason=failed exit=1 status=0 -- The helper can fail before observing completion.
        // expected-log: tui: wait=acme.tui/hello run=1-1 reason=unstarted -- A wait Process can fail to start.
        // expected-log: tui: wait=acme.tui/hello run=1-1 reason=failed exit=9 status=1 -- A crashed wait is not presenter completion.
        // expected-log: tui: wait=acme.tui/hello run=1-1 reason=stdout-lines count=0 -- A successful process without a result proves no completion.
        function test_failed_wait_keeps_the_run_live_until_completion(data) {
            addDone();
            records.launched(key, run);
            const reader = readerOf(runningPath);
            if (data.readFirst)
                finishRead(runningPath, JSON.stringify(record("running", null)));
            const pendingWait = waitProcesses()[0];
            if (data.startFailed) pendingWait.failStart();
            else pendingWait.finish(data.code, data.status, "", "");
            if (!data.readFirst)
                finishRead(runningPath, JSON.stringify(record("running", null)));
            model.setFiles(data.listed ? [runningPath] : [], "reset");
            compare(records.readers[runningPath], reader);
            compare(records.record().runs[key].running, run);
            compare(JSON.stringify(events), "[]");
            compare(records.record().waiters, ["core"]);
            compare(waitProcesses().length, 0);
            // Completion through the listing releases a failed wait's hold,
            // even when the listing never included the running record.
            model.setFiles(data.listed ? [runningPath, endedPath] : [endedPath], "insert");
            finishRead(endedPath, JSON.stringify(record("ended", 9)));
            compare(records.record().runs[key].running, null);
            compare(records.launchedRuns, []);
            compare(JSON.stringify(events), JSON.stringify([{ code: 9, reason: null, package: null }]));
            if (!data.listed)
                compare(Object.keys(records.readers), [endedPath]);
            model.setFiles([], "remove");
            wait(0);
            compare(Object.keys(records.readers), []);
            compare(Object.keys(records.fileRecords), []);
            compare(waitProcesses().length, 0);
            compare(JSON.stringify(events), JSON.stringify([{ code: 9, reason: null, package: null }]));
        }

        // The listing keeps the first run's running record through a second
        // run of the key: the second run's wait record must not bring the
        // first run back to running, nor start another wait for it.
        function test_a_stale_listing_across_two_runs_keeps_the_first_ended() {
            addDone();
            listRunning();
            model.setFiles([runningPath, endedPath], "drop");
            finishWait(7);
            const second = Object.assign(record("ended", 4), { run: "2-1", startedAt: "2026-09-29T07:00:02.000Z", endedAt: "2026-09-29T07:00:03.000Z" });
            const secondEvents = [];
            records.addWaiter("core", "2-1", result => secondEvents.push(result));
            records.launched(key, "2-1");
            const waits = waitProcesses();
            compare(waits.length, 1);
            waits[0].finish(0, 0, JSON.stringify(second) + "\n", "");
            compare(JSON.stringify(secondEvents), JSON.stringify([{ code: 4, reason: null, package: null }]));
            compare(records.runs.keys[key].running, null);
            compare(records.runs.keys[key].ended.run, "2-1");
            compare(waitProcesses().length, 0);
        }

        // The presenter's typed package outcome reaches `done` on either
        // path, the wait's line or the listed file, as the ended record
        // carries it; one the judge refuses keeps the run's generic end.
        function test_an_ended_record_hands_done_its_package_outcome_data() {
            return [
                { tag: "wait", listed: false },
                { tag: "listing", listed: true }
            ];
        }

        function test_an_ended_record_hands_done_its_package_outcome(data) {
            const outcome = { kind: "package-check-failed", manager: "pacman", helper: "paru", package: "ttfx", status: 1, retry: { originRun: run, state: "available" } };
            const ended = Object.assign(record("ended", 1), { package: outcome });
            addDone();
            listRunning();
            if (data.listed) {
                model.setFiles([runningPath, endedPath], "insert");
                finishRead(endedPath, JSON.stringify(ended));
            } else {
                waitProcesses()[0].finish(0, 0, JSON.stringify(ended) + "\n", "");
            }
            compare(JSON.stringify(events), JSON.stringify([{ code: 1, reason: null, package: outcome }]));
            verify(Object.isFrozen(events[0].package.retry), "the outcome reaches done frozen");
        }

        // The smoke shell-log check parses the package-outcome category.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.ended.json package-outcome=unavailable reason=retry-run -- A retry of another run is no outcome of this one.
        function test_a_refused_package_outcome_keeps_the_generic_end() {
            const foreign = { kind: "package-check-failed", manager: "pacman", helper: "paru", package: "ttfx", status: 1, retry: { originRun: "9-9", state: "available" } };
            addDone();
            listRunning();
            model.setFiles([runningPath, endedPath], "insert");
            finishRead(endedPath, JSON.stringify(Object.assign(record("ended", 1), { package: foreign })));
            compare(JSON.stringify(events), JSON.stringify([{ code: 1, reason: null, package: null }]));
            compare(records.runs.keys[key].running, null);
        }

        function runPath(id, state) {
            return "/unit/tui/acme.tui@hello@" + id + "." + state + ".json";
        }

        function runRecord(id, state, code, second) {
            return Object.assign(record(state, code), {
                run: id,
                startedAt: "2026-09-29T07:00:0" + second + ".000Z",
                endedAt: state === "ended" ? "2026-09-29T07:00:0" + (second + 1) + ".000Z" : null
            });
        }

        function listAndRead(files, signalName, path, text) {
            model.setFiles(files, signalName);
            finishRead(path, text);
        }

        function waitOf(id) {
            const waits = waitProcesses().filter(process => process.command[5] === id);
            compare(waits.length, 1, "one wait for run " + id);
            return waits[0];
        }

        // Back to back: run 1-1's ended record is read from the listing, run
        // 2-1 of the same key starts, and 2-1's presenter removes 1-1's
        // records before 1-1's wait reads them, so that wait ends with the
        // gone code, 3. The core already delivered 1-1's done and 2-1's wait
        // stays live. Whether the gone end logs a line is
        // PluginLogic.tuiWaitOutcome's decision, pinned with its controls by
        // scripts/test-tui-logic.js; this harness does not capture the log,
        // so no edit to that decision reddens this test. It holds that the
        // gone end changes no run, delivers no second done, starts no new
        // wait, and leaves the later run's wait to deliver its own done.
        function test_a_gone_wait_of_an_ended_run_leaves_the_next_run_alone() {
            const firstEvents = [];
            const secondEvents = [];
            records.addWaiter("core", "1-1", result => firstEvents.push(result));
            records.launched(key, "1-1");
            const firstWait = waitOf("1-1");
            listAndRead([runPath("1-1", "running")], "reset", runPath("1-1", "running"), JSON.stringify(runRecord("1-1", "running", null, 0)));
            listAndRead([runPath("1-1", "running"), runPath("1-1", "ended")], "insert", runPath("1-1", "ended"), JSON.stringify(runRecord("1-1", "ended", 0, 0)));
            compare(JSON.stringify(firstEvents), JSON.stringify([{ code: 0, reason: null, package: null }]));
            verify(firstWait.running, "the first run's wait still runs after the listing ended the run");

            records.addWaiter("core", "2-1", result => secondEvents.push(result));
            records.launched(key, "2-1");
            const secondWait = waitOf("2-1");
            listAndRead([runPath("1-1", "ended"), runPath("2-1", "running")], "reset", runPath("2-1", "running"), JSON.stringify(runRecord("2-1", "running", null, 2)));
            model.setFiles([runPath("2-1", "running")], "remove");
            compare(records.runs.runs["1-1"], undefined);
            compare(records.record().waits, [key + "|1-1", key + "|2-1"]);

            firstWait.finish(3, 0, "", "vgshell-tui: refused: wait=acme.tui/hello run=1-1 reason=gone\n");
            compare(JSON.stringify(firstEvents), JSON.stringify([{ code: 0, reason: null, package: null }]));
            compare(records.runs.keys[key].running.run, "2-1");
            compare(records.record().waits, [key + "|2-1"]);
            verify(secondWait.running, "the later run's wait is still live");
            compare(JSON.stringify(secondEvents), JSON.stringify([]));

            secondWait.finish(0, 0, JSON.stringify(runRecord("2-1", "ended", 4, 2)) + "\n", "");
            compare(JSON.stringify(secondEvents), JSON.stringify([{ code: 4, reason: null, package: null }]));
            compare(JSON.stringify(firstEvents), JSON.stringify([{ code: 0, reason: null, package: null }]));
            compare(records.runs.keys[key].running, null);
            compare(records.record().waits, []);
            compare(waitProcesses().length, 0);
        }
    }
}
