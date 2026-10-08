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

        function reads() {
            return ProcessRegistry.processes.filter(process => process.running && process.command[0] === "cat");
        }

        // The reader the listing started for path: one cat of that path
        // under the PATH-only environment.
        function readerOf(path) {
            verify(Object.prototype.hasOwnProperty.call(records.readers, path), "the record gets a reader: " + path);
            const reader = records.readers[path];
            verify(reader.running, "the listing started the read of " + path);
            compare(reader.command, ["cat", "--", path]);
            compare(reader.clearEnvironment, true);
            compare(reader.environment, { PATH: "env:PATH" });
            compare(ProcessRegistry.runningWithVerb("-e").length, 0);
            return reader;
        }

        // A read that succeeds starts no existence probe.
        function finishRead(path, text) {
            readerOf(path).finish(0, 0, text, "");
            compare(ProcessRegistry.runningWithVerb("-e").length, 0);
        }

        function listRunning() {
            model.setFiles([runningPath], "reset");
            finishRead(runningPath, JSON.stringify(record("running", null)));
        }

        function probeOf(path) {
            const probes = ProcessRegistry.runningWithVerb("-e");
            compare(probes.length, 1);
            compare(probes[0].command, ["test", "-e", path]);
            compare(probes[0].clearEnvironment, true);
            compare(probes[0].environment, { PATH: "env:PATH" });
            return probes[0];
        }

        // Ends the listed record's read as end says: a failed start, or an
        // exit with its code, status and cat's message.
        function failListedRead(end, removed) {
            model.setFiles([runningPath], "reset");
            const reader = readerOf(runningPath);
            // A removed file stays listed until the directory change arrives.
            if (removed) model.setFiles([], "drop");
            if (end.startFailed) reader.failStart();
            else reader.finish(end.code, end.status, "", end.err);
            compare(Object.keys(records.fileRecords), []);
            return probeOf(runningPath);
        }

        readonly property var denied: ({ code: 1, status: 0, err: "cat: /unit/tui/acme.tui@hello@1-1.running.json: Permission denied\n" })

        function test_removed_record_read_failure_data() {
            // A removal can also end the read without cat's not-found exit.
            return [
                { tag: "crash", end: { code: 9, status: 1, err: "" } }
            ];
        }

        function test_removed_record_read_failure(data) {
            const probe = failListedRead(data.end, true);
            probe.finish(1, 0);
            compare(Object.keys(records.fileRecords), []);
            compare(waitProcesses().length, 0);
        }

        // The writer removes a listed record before the shell reads it: cat
        // exits 1 not found and the probe confirms the removal. The case
        // declares no expected log, so qml-unit.sh fails it on any warning
        // or error line, the failed read's included.
        function test_a_record_removed_during_its_read_logs_nothing() {
            const probe = failListedRead({ code: 1, status: 0, err: "cat: " + runningPath + ": No such file or directory\n" }, true);
            probe.finish(1, 0);
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
            if (data.ok) reader.finish(0, 0, JSON.stringify(record("running", null)), "");
            else reader.finish(1, 0, "", denied.err);
            compare(Object.keys(records.fileRecords), []);
            compare(ProcessRegistry.runningWithVerb("-e").length, 0);
            wait(0);
            compare(Object.keys(records.readers), []);
            compare(Object.keys(records.fileRecords), []);
        }

        function test_existing_record_read_failure_data() {
            return [
                { tag: "unreadable", end: denied },
                { tag: "failed-start", end: { startFailed: true } },
                { tag: "crash", end: { code: 9, status: 1, err: "" } },
                { tag: "reappeared", end: { code: 1, status: 0, err: "cat: /unit/tui/acme.tui@hello@1-1.running.json: No such file or directory\n" } }
            ];
        }

        // The smoke shell-log check parses the tui: record= error line.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: start=failed -- An existing record whose read failed to start must remain an error.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: code=9 status=1 -- An existing record whose read crashed must remain an error.
        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: code=1 status=0 -- An existing record whose read exited 1 must remain an error.
        function test_existing_record_read_failure(data) {
            const probe = failListedRead(data.end);
            probe.finish(0, 0);
            compare(Object.keys(records.fileRecords), []);
            compare(ProcessRegistry.runningWithVerb("-e").length, 0);
        }

        function test_unconfirmed_existence_data() {
            return [
                { tag: "failed-start", startFailed: true, code: 0, status: 0 },
                { tag: "crash", startFailed: false, code: 1, status: 1 },
                { tag: "unexpected-exit", startFailed: false, code: 2, status: 0 }
            ];
        }

        // expected-log: tui: record=/unit/tui/acme.tui@hello@1-1.running.json unreadable: code=1 status=0 -- A failed existence check cannot confirm a removal.
        function test_unconfirmed_existence(data) {
            const probe = failListedRead(denied);
            if (data.startFailed) probe.failStart();
            else probe.finish(data.code, data.status);
            compare(Object.keys(records.fileRecords), []);
        }

        function test_removal_destroys_an_outstanding_reader_process_data() {
            return [
                { tag: "read", failed: false },
                { tag: "existence-check", failed: true }
            ];
        }

        function test_removal_destroys_an_outstanding_reader_process(data) {
            if (data.failed) {
                failListedRead(denied);
            } else {
                model.setFiles([runningPath], "reset");
                readerOf(runningPath);
            }
            model.setFiles([], "remove");
            wait(0);
            compare(Object.keys(records.readers), []);
            compare(reads().length, 0);
            compare(ProcessRegistry.runningWithVerb("-e").length, 0);
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
            compare(JSON.stringify(events), JSON.stringify([{ code: 7, reason: null }]));
            compare(records.runs.keys[key].running, null);
            compare(records.record().waits, []);
            wait(0);
            compare(JSON.stringify(events), JSON.stringify([{ code: 7, reason: null }]));
        }

        function test_listing_end_before_wait_calls_done_once() {
            addDone();
            listRunning();
            model.setFiles([runningPath, endedPath], "insert");
            finishRead(endedPath, JSON.stringify(record("ended", 3)));
            compare(JSON.stringify(events), JSON.stringify([{ code: 3, reason: null }]));
            finishWait(3);
            compare(JSON.stringify(events), JSON.stringify([{ code: 3, reason: null }]));
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
            compare(JSON.stringify(events), JSON.stringify([{ code: null, reason: "vanished" }]));
            compare(records.runs.keys[key].running, null);
        }

        function test_launched_run_starts_wait_without_a_listing() {
            addDone();
            records.launched(key, run);
            compare(waitProcesses().length, 1);
            finishWait(9);
            compare(JSON.stringify(events), JSON.stringify([{ code: 9, reason: null }]));
            compare(records.runs.keys[key].ended.run, run);
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
            compare(JSON.stringify(secondEvents), JSON.stringify([{ code: 4, reason: null }]));
            compare(records.runs.keys[key].running, null);
            compare(records.runs.keys[key].ended.run, "2-1");
            compare(waitProcesses().length, 0);
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
            compare(JSON.stringify(firstEvents), JSON.stringify([{ code: 0, reason: null }]));
            verify(firstWait.running, "the first run's wait still runs after the listing ended the run");

            records.addWaiter("core", "2-1", result => secondEvents.push(result));
            records.launched(key, "2-1");
            const secondWait = waitOf("2-1");
            listAndRead([runPath("1-1", "ended"), runPath("2-1", "running")], "reset", runPath("2-1", "running"), JSON.stringify(runRecord("2-1", "running", null, 2)));
            model.setFiles([runPath("2-1", "running")], "remove");
            compare(records.runs.runs["1-1"], undefined);
            compare(records.record().waits, [key + "|1-1", key + "|2-1"]);

            firstWait.finish(3, 0, "", "vgshell-tui: refused: wait=acme.tui/hello run=1-1 reason=gone\n");
            compare(JSON.stringify(firstEvents), JSON.stringify([{ code: 0, reason: null }]));
            compare(records.runs.keys[key].running.run, "2-1");
            compare(records.record().waits, [key + "|2-1"]);
            verify(secondWait.running, "the later run's wait is still live");
            compare(JSON.stringify(secondEvents), JSON.stringify([]));

            secondWait.finish(0, 0, JSON.stringify(runRecord("2-1", "ended", 4, 2)) + "\n", "");
            compare(JSON.stringify(secondEvents), JSON.stringify([{ code: 4, reason: null }]));
            compare(JSON.stringify(firstEvents), JSON.stringify([{ code: 0, reason: null }]));
            compare(records.runs.keys[key].running, null);
            compare(records.record().waits, []);
            compare(waitProcesses().length, 0);
        }
    }
}
