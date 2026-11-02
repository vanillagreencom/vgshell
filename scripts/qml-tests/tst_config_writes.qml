import QtQuick
import QtTest
import qs.Core
import Quickshell.Io

// Config's one writer against the stand-in FileView, whose reads the test
// finishes by hand: a user-file write made from a handler of a change that
// a write or a read of that file brings is on the file, and in `effective`,
// beside the change that ran the handler, the write that returns the file
// to its earlier bytes included. An object here reads a value of
// `Config.effective` as a plugin's settings do and writes from its change
// handler, building on `Config.user` as the core's edits do. A rename map
// the scan hands Config renames a former plugin id in the loaded file with
// one write, and in a file read after it before anything is published.
Item {
    id: root

    // In the writer's own form, so a write that returns the file to it
    // writes the bytes the file held before.
    readonly property string baseText: JSON.stringify({ version: 4 }, null, 2) + "\n"

    // Adds `nested` once the outer write's `outer` arrives.
    Component {
        id: addsComponent
        QtObject {
            property var answers: []
            readonly property var outer: Config.effective.outer
            onOuterChanged: {
                if (outer === 1) answers.push(Config.writeUser(Object.assign({}, Config.user, { nested: 2 })));
            }
        }
    }

    // Takes `notice` out again as soon as a write sets it, as the Updates
    // service clears its Reboot notice request.
    Component {
        id: clearsComponent
        QtObject {
            property var answers: []
            readonly property var notice: Config.effective.notice
            onNoticeChanged: {
                if (notice === undefined) return;
                const user = Object.assign({}, Config.user);
                delete user.notice;
                answers.push(Config.writeUser(user));
            }
        }
    }

    // Adds `nested` once a read brings `read`.
    Component {
        id: readsComponent
        QtObject {
            property var answers: []
            readonly property var read: Config.effective.read
            onReadChanged: {
                if (read === 1) answers.push(Config.writeUser(Object.assign({}, Config.user, { nested: 2 })));
            }
        }
    }

    // Writes the next count on every change of `count`, a writer that
    // never settles, up to `cap`, far past publish()'s bound, so a publish
    // with no bound ends rather than hangs the run.
    Component {
        id: countsComponent
        QtObject {
            readonly property int cap: 200
            property int writes: 0
            readonly property var count: Config.effective.count
            onCountChanged: {
                if (count === undefined || writes === cap) return;
                writes += 1;
                Config.writeUser(Object.assign({}, Config.user, { count: writes }));
            }
        }
    }

    // Every value of `Config.effective.disabledPlugins` a reader is told.
    Component {
        id: disabledSeenComponent
        QtObject {
            property var seen: []
            readonly property var disabled: Config.effective.disabledPlugins
            onDisabledChanged: seen.push(disabled === undefined ? null : disabled.slice())
        }
    }

    // Records how far the writer got when the event loop next ran a timer.
    Timer {
        id: turn
        property int writesSeen: -1
        interval: 0
    }

    TestCase {
        name: "config-writes"

        // The WatchedFile of `path` among Config's children.
        function watched(path) {
            for (let i = 0; i < Config.data.length; i++) {
                if (Config.data[i].path === path) return Config.data[i];
            }
            fail("no watched file path=" + path);
        }

        // The view of `path` that reads and writes: the stand-in holds the
        // bytes a write left in `content`.
        function view(path) {
            return watched(path).data[1];
        }

        function finishNextRead(path, bytes) {
            const file = watched(path);
            if (!file.busy) file.read();
            tryCompare(view(path), "live", "read");
            view(path).finishRead(bytes);
            compare(file.busy, false);
        }

        function fileHolds(expected) {
            compare(JSON.parse(view(Config.userPath).content), expected);
        }

        function compareReader() {
            for (let i = 0; i < Config.data.length; i++) {
                const child = Config.data[i];
                if (child.path === Config.userPath && typeof child.waitForJob === "function") return child;
            }
            fail("no package review compare reader");
        }

        function test_package_review_write_preserves_absence_and_other_settings() {
            const user = { version: 4, packages: { elevate: "doas", review: { agent: "codex", command: "" } }, unrelated: { keep: true } };
            const bytes = JSON.stringify(user);
            finishNextRead(Config.userPath, bytes);
            const reader = compareReader();
            reader.blockingError = 0;
            reader.blockingContent = bytes;
            compare(Config.packageReviewWrite(JSON.stringify({ expectedText: bytes, settings: { agent: "codex", command: "codex custom" } })), "ok");
            compare(Config.user.packages, { elevate: "doas", review: { agent: "codex", command: "codex custom" } });
            compare(Config.user.unrelated, { keep: true });
            verify(!Object.prototype.hasOwnProperty.call(Config.user.packages.review, "enabled"));
        }

        function test_retired_shortcuts_use_shipped_migration_data_and_write_current_values() {
            const replacements = [{ id: "acme.keys", shortcut: "talk", from: "SUPER+code:108", to: "SUPER+code:30" }];
            try {
                finishNextRead(Config.shippedPath, JSON.stringify({ version: 4, shortcutKeyMigrations: replacements }));
                finishNextRead(Config.userPath, JSON.stringify({ version: 3, plugins: [{ id: "acme.keys", keys: { talk: "super+CODE:00108", mute: null }, keep: true }] }));
                const want = { version: 4, plugins: [{ id: "acme.keys", keys: { talk: "SUPER+code:30", mute: null }, keep: true }] };
                compare(Config.user, want);
                fileHolds(want);
                finishNextRead(Config.userPath, JSON.stringify(want));
                compare(Config.user, want);
            } finally {
                finishNextRead(Config.shippedPath, root.baseText);
            }
        }

        function test_package_review_write_refuses_concurrent_unreadable_and_invalid_changes() {
            const reader = compareReader();
            const bytes = Config.userText;
            const request = JSON.stringify({ expectedText: bytes, settings: { enabled: false, agent: "missing", command: "" } });
            reader.blockingError = 0;
            reader.blockingContent = bytes + " ";
            verify(Config.packageReviewWrite(request) !== "ok");
            compare(Config.userText, bytes);
            reader.blockingError = FileViewError.PermissionDenied;
            verify(Config.packageReviewWrite(request) !== "ok");
            compare(Config.userText, bytes);
            reader.blockingError = 0;
            reader.blockingContent = bytes;
            verify(Config.packageReviewWrite(JSON.stringify({ expectedText: bytes, settings: { enabled: "false" } })) !== "ok");
            compare(Config.userText, bytes);
        }

        function initTestCase() {
            finishNextRead(Config.shippedPath, root.baseText);
            finishNextRead(Config.userPath, root.baseText);
            compare(Config.ready, true);
        }

        // Every case starts from a read of the file holding the version
        // alone, whatever an earlier case wrote.
        function init() {
            finishNextRead(Config.userPath, "{\"version\": 4, \"reset\": true}\n");
            finishNextRead(Config.userPath, root.baseText);
            compare(Config.user, { version: 4 });
            compare(Config.effective, { version: 4 });
        }

        // No case's rename map reaches the next case's reads.
        function cleanup() {
            Config.adoptRenames({});
        }

        function test_a_rename_after_load_writes_once() {
            finishNextRead(Config.userPath, "{\"version\": 4, \"disabledPlugins\": [\"acme.old\"], \"bar\": {\"layout\": {\"right\": [{\"id\": \"acme.old\"}]}}}\n");
            compare(Config.effective.disabledPlugins, ["acme.old"]);
            let saves = 0;
            const counted = () => { saves += 1; };
            watched(Config.userPath).saved.connect(counted);
            Config.adoptRenames({ "acme.old": "acme.new" });
            Config.adoptRenames({ "acme.old": "acme.new" });
            watched(Config.userPath).saved.disconnect(counted);
            compare(saves, 1);
            const renamed = { version: 4, disabledPlugins: ["acme.new"], bar: { layout: { right: [{ id: "acme.new" }] } } };
            fileHolds(renamed);
            compare(Config.user, renamed);
            compare(Config.effective, renamed);
        }

        function test_a_load_after_adopt_renames_publishes_the_new_id_first() {
            const disabled = createTemporaryObject(disabledSeenComponent, root);
            Config.adoptRenames({ "acme.old": "acme.new" });
            finishNextRead(Config.userPath, "{\"version\": 4, \"disabledPlugins\": [\"acme.old\"]}\n");
            compare(disabled.seen, [["acme.new"]]);
            fileHolds({ version: 4, disabledPlugins: ["acme.new"] });
            compare(Config.effective, { version: 4, disabledPlugins: ["acme.new"] });
        }

        // expected-log: config: user file not written at -- the planted write failure
        // expected-log: config: user file plugins renamed in memory, not written -- the rename the disk refused
        function test_a_rename_the_disk_refuses_is_renamed_in_memory() {
            finishNextRead(Config.userPath, "{\"version\": 4, \"disabledPlugins\": [\"acme.old\"]}\n");
            view(Config.userPath).failNextWrite = 28;
            Config.adoptRenames({ "acme.old": "acme.new" });
            verify(Config.saveError !== "", "saveError=" + Config.saveError);
            compare(Config.user, { version: 4, disabledPlugins: ["acme.new"] });
            compare(Config.effective, { version: 4, disabledPlugins: ["acme.new"] });
        }

        readonly property var splitClaims: [{ from: "acme.source", to: "acme.split", keys: ["keep"] }]

        function test_split_after_rename_writes_once_and_repeated_reads_do_nothing() {
            finishNextRead(Config.userPath, JSON.stringify({ version: 4, disabledPlugins: ["acme.old"], plugins: [{ id: "acme.old", keep: false, retired: 1 }] }));
            let saves = 0;
            const counted = () => { saves += 1; };
            watched(Config.userPath).saved.connect(counted);
            Config.adoptRenames({ "acme.old": "acme.source" }, splitClaims);
            const want = { version: 4, disabledPlugins: ["acme.source", "acme.split"], plugins: [{ id: "acme.source", keep: false, retired: 1 }, { id: "acme.split", keep: false }] };
            fileHolds(want);
            Config.adoptRenames({ "acme.old": "acme.source" }, splitClaims);
            finishNextRead(Config.userPath, JSON.stringify(want));
            compare(saves, 1);
            watched(Config.userPath).saved.disconnect(counted);
            compare(Config.effective, want);
        }

        function test_every_user_read_splits_before_publishing_once() {
            Config.adoptRenames({}, splitClaims);
            const disabled = createTemporaryObject(disabledSeenComponent, root);
            let saves = 0;
            const counted = () => { saves += 1; };
            watched(Config.userPath).saved.connect(counted);
            const bytes = JSON.stringify({ version: 4, disabledPlugins: ["acme.source"] });
            finishNextRead(Config.userPath, bytes);
            const want = { version: 4, disabledPlugins: ["acme.source", "acme.split"], plugins: [{ id: "acme.split" }] };
            compare(disabled.seen, [["acme.source", "acme.split"]]);
            fileHolds(want);
            // A later external edit can again predate this declaration.
            finishNextRead(Config.userPath, bytes + "\n");
            compare(saves, 2);
            watched(Config.userPath).saved.disconnect(counted);
            compare(Config.effective, want);
        }

        function test_missing_file_marks_every_split_without_copying_new_disables() {
            Config.adoptRenames({}, splitClaims.concat([{ from: "acme.other", to: "acme.another", keys: [] }]));
            watched(Config.userPath).read();
            view(Config.userPath).failRead(FileViewError.FileNotFound);
            compare(Config.userState, "absent");
            compare(Config.writeUser({ version: 4, disabledPlugins: ["acme.source"] }), "ok");
            const want = { version: 4, disabledPlugins: ["acme.source"], plugins: [{ id: "acme.split" }, { id: "acme.another" }] };
            fileHolds(want);
            finishNextRead(Config.userPath, JSON.stringify(want));
            compare(Config.effective, want);
        }

        function test_write_from_a_write_handler_keeps_both() {
            const adds = createTemporaryObject(addsComponent, root);
            compare(Config.writeUser({ version: 4, outer: 1 }), "ok");
            compare(adds.answers, ["ok"]);
            fileHolds({ version: 4, outer: 1, nested: 2 });
            compare(Config.user, { version: 4, outer: 1, nested: 2 });
            compare(Config.effective, { version: 4, outer: 1, nested: 2 });
        }

        function test_write_back_to_the_earlier_bytes_is_written() {
            const clears = createTemporaryObject(clearsComponent, root);
            for (const round of [1, 2]) {
                compare(Config.writeUser({ version: 4, notice: "round-" + round }), "ok");
                compare(clears.answers.length, round);
                compare(clears.answers[round - 1], "ok");
                fileHolds({ version: 4 });
                compare(Config.user, { version: 4 });
                compare(Config.effective, { version: 4 });
            }
        }

        function test_write_from_a_read_handler_keeps_both() {
            const reads = createTemporaryObject(readsComponent, root);
            finishNextRead(Config.userPath, "{\"version\": 4, \"read\": 1}\n");
            compare(reads.answers, ["ok"]);
            fileHolds({ version: 4, read: 1, nested: 2 });
            compare(Config.user, { version: 4, read: 1, nested: 2 });
            compare(Config.effective, { version: 4, read: 1, nested: 2 });
        }

        // The warning is taken by ignoreWarning, which fails the case when
        // it is not logged; a second one is a line no declaration covers.
        function test_writer_that_never_settles_yields_to_the_event_loop() {
            const counts = createTemporaryObject(countsComponent, root);
            const seen = () => { turn.writesSeen = counts.writes; };
            turn.triggered.connect(seen);
            ignoreWarning(/^config: publish did not settle: repeats=16 file=.* writer=expression for onCountChanged@.*tst_config_writes\.qml:/);
            turn.start();
            compare(Config.writeUser({ version: 4, count: 0 }), "ok");
            verify(counts.writes > 1 && counts.writes < counts.cap, "writes=" + counts.writes);
            tryVerify(() => turn.writesSeen >= 0, 5000);
            verify(turn.writesSeen < counts.cap, "writes=" + turn.writesSeen);
            tryCompare(counts, "writes", counts.cap, 5000);
            fileHolds({ version: 4, count: counts.cap });
            compare(Config.user, { version: 4, count: counts.cap });
            compare(Config.effective, { version: 4, count: counts.cap });
            turn.triggered.disconnect(seen);
        }
    }
}
