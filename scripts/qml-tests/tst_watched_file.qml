import QtQuick
import QtTest
import qs.Commons

// WatchedFile against the stand-in FileView, whose reads the test finishes
// by hand: a change or a read() during a read drops that read's result and
// reads again, a failed read included; a change while no read is in flight
// is reported and starts nothing; the watching view is never read or
// reloaded and the reading view watches nothing; a write is on the view and
// reported before write() returns, a failed one included; a write during a
// read is followed by a read; and a read or a write asked from a result
// handler still reaches the view.
Item {
    id: root

    Component {
        id: fileComponent
        WatchedFile { path: "/unit/watched.json" }
    }

    TestCase {
        name: "watched-file"

        property var file: null
        property var watcher: null
        property var reader: null
        property var events: []

        function init() {
            file = createTemporaryObject(fileComponent, root);
            verify(file !== null, "the file builds");
            watcher = file.data[0];
            reader = file.data[1];
            events = [];
            file.loaded.connect(content => events.push("loaded:" + content));
            file.loadFailed.connect(error => events.push("failed:" + error));
            file.saved.connect(() => events.push("saved"));
            file.saveFailed.connect(error => events.push("save-failed:" + error));
            file.changed.connect(() => events.push("changed"));
        }

        function settleFirst() {
            reader.finishRead("first");
            compare(file.busy, false);
            events = [];
        }

        function test_first_read_is_reported() {
            compare(reader.reads, 1);
            compare(file.busy, true);
            reader.finishRead("a");
            compare(events, ["loaded:a"]);
            compare(file.busy, false);
        }

        function test_watching_view_is_never_read() {
            settleFirst();
            watcher.change();
            file.read();
            tryCompare(reader, "reads", 2);
            reader.finishRead("b");
            compare(watcher.reads, 0);
            compare(watcher.reloads, 0);
            compare(watcher.watchers, 1);
            compare(reader.watchers, 0);
        }

        function test_change_during_read_reads_again() {
            watcher.change();
            reader.finishRead("old");
            compare(events, []);
            tryCompare(reader, "reads", 2);
            reader.finishRead("new");
            compare(events, ["loaded:new"]);
            compare(file.busy, false);
        }

        function test_read_during_read_reads_again() {
            settleFirst();
            file.read();
            tryCompare(reader, "reads", 2);
            file.read();
            reader.finishRead("old");
            compare(events, []);
            tryCompare(reader, "reads", 3);
            reader.finishRead("new");
            compare(events, ["loaded:new"]);
        }

        function test_overtaken_failed_read_reads_again() {
            watcher.change();
            reader.failRead(2);
            compare(events, []);
            tryCompare(reader, "reads", 2);
            reader.finishRead("back");
            compare(events, ["loaded:back"]);
        }

        function test_change_while_idle_is_reported() {
            settleFirst();
            watcher.change();
            compare(events, ["changed"]);
            wait(0);
            compare(reader.reads, 1);
        }

        function test_write_is_reported_before_it_returns() {
            settleFirst();
            file.write("w");
            compare(reader.written, "w");
            compare(events, ["saved"]);
            compare(file.busy, false);
        }

        function test_failed_write_is_reported_before_it_returns() {
            settleFirst();
            reader.failNextWrite = 7;
            file.write("w");
            compare(events, ["save-failed:7"]);
            compare(file.busy, false);
        }

        function test_write_during_read_is_followed_by_a_read() {
            file.write("w");
            compare(reader.written, "w");
            compare(events, ["saved"]);
            compare(reader.live, "");
            tryCompare(reader, "reads", 2);
            compare(events, ["saved"]);
            reader.finishRead("w");
            compare(events, ["saved", "loaded:w"]);
            compare(file.busy, false);
        }

        function test_read_from_a_result_handler_reaches_the_view() {
            settleFirst();
            let asked = false;
            file.loaded.connect(() => { if (!asked) { asked = true; file.read(); } });
            file.read();
            tryCompare(reader, "reads", 2);
            reader.finishRead("x");
            tryCompare(reader, "reads", 3);
            reader.finishRead("y");
            compare(events, ["loaded:x", "loaded:y"]);
            compare(file.busy, false);
        }

        function test_write_from_a_result_handler_reaches_the_view() {
            let asked = false;
            file.loaded.connect(() => { if (!asked) { asked = true; file.write("w"); } });
            reader.finishRead("x");
            compare(reader.written, "w");
            compare(events, ["loaded:x", "saved"]);
            compare(file.busy, false);
        }
    }
}
