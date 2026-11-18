import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import qs.Commons

// ThemeRunner against the stand-in Process, whose jobs the test finishes
// by hand, with a reader bound to `last` that queues reads from its change
// handler as the themes service does: `last` changes only when the apply
// running, the last result or the download's progress changes, so a read
// queued from a reader's handler changes nothing the reader is bound to.
// The run fails on any warning, a binding loop's included.
Item {
    id: root

    Component {
        id: runnerComponent
        ThemeRunner {}
    }

    Component {
        id: readerComponent
        QtObject {
            property var runner: null
            property var context: null
            property int refreshes: 0
            property bool sawDownload: false
            readonly property var download: runner.last.downloading
            onDownloadChanged: {
                if (sawDownload && download === null) {
                    refreshes++;
                    runner.list(context, () => {});
                    runner.images(context, "all", () => {});
                    runner.catalog(context, () => {});
                }
                sawDownload = download !== null;
            }
        }
    }

    TestCase {
        name: "theme-runner"

        readonly property var context: ({ id: "unit", onDispose: () => () => {} })
        property var runner: null
        property int lastChanges: 0

        function init() {
            runner = createTemporaryObject(runnerComponent, root, { notificationHub: { holdsName: false, active: false } });
            verify(runner !== null, "the runner builds");
            lastChanges = 0;
            runner.lastChanged.connect(() => lastChanges++);
        }

        // The one job process running, once the queued start has run.
        function started() {
            const mine = () => ProcessRegistry.runningWithVerb("theme").filter(process => process.job !== null && process.job.started);
            tryVerify(() => mine().length === 1, 1000, "one job process runs");
            return mine()[0];
        }

        function finishJob(process, answer) {
            process.stdout.read(JSON.stringify(answer));
            process.exited(0, 0);
            process.running = false;
        }

        function test_readability_report_link_follows_successful_write_data() {
            return [{ tag: "saved", state: "saved" }, { tag: "write failed", state: "failed" },
                { tag: "commit lost", state: "lost" }, { tag: "read refused", state: "unreadable" }, { tag: "no shortfalls", state: "empty" }];
        }

        // expected-log: theme: readability-report path= -- Refused writes and failed readbacks log their own cause before a notice without a link.
        function test_readability_report_link_follows_successful_write(row) {
            const result = { state: "applied", shell: "applied", theme: "vgs", readabilityShortfalls: [
                { text: "color.textFaint", surface: "color.background", ratio: 1, floor: 4.5 }
            ] };
            if (row.state === "empty") result.readabilityShortfalls = [];
            const file = findChild(runner, "themeReadabilityReport");
            verify(file !== null);
            const notices = () => ProcessRegistry.processes.filter(process => process.pluginId === "core" && process.running);
            const before = notices().length;
            compare(runner.completed("apply", JSON.stringify(result)), "ok");
            compare(file.live, "write");
            verify(file.written.length > 0);
            compare(notices().length, before, "a pending write publishes no link");
            const saved = row.state === "saved" || row.state === "empty";
            file.live = "";
            if (row.state === "failed") file.saveFailed(FileViewError.PermissionDenied);
            else {
                file.saved();
                tryCompare(file, "live", "read");
                compare(notices().length, before, "a saved signal alone proves no report");
                if (row.state === "unreadable") file.failRead(FileViewError.PermissionDenied);
                else file.finishRead(saved ? file.written : "stale report");
            }
            compare(runner.readabilityWrites.length, 0);
            if (row.state === "empty") {
                compare(notices().length, before, "a clean check replaces the latest report without a warning");
                return;
            }
            compare(notices().length, before + 1);
            const notice = notices()[notices().length - 1];
            const references = notice.command.filter(argument => argument.indexOf("--hint=string:x-vgs-page:") === 0);
            compare(references.length, saved ? 1 : 0);
            if (saved) compare(PageReference.file(PageReference.parse(references[0].slice("--hint=string:x-vgs-page:".length)).page), runner.readabilityPath);
            notice.exited(0, 0);
            notice.running = false;
        }

        function test_reads_queued_at_a_download_end_leave_last_alone() {
            const reader = createTemporaryObject(readerComponent, root, { runner: runner, context: context });
            let answers = 0;
            compare(runner.wallpapers(context, "scenic", () => answers++), "ok");
            const process = started();
            compare(runner.last.downloading.name, "scenic");
            compare(lastChanges, 1);
            finishJob(process, { state: "installed", theme: "scenic", wallpapers: null, images: null, sha256: null, reason: null });
            compare(answers, 1);
            compare(reader.refreshes, 1);
            compare(runner.jobs.map(job => job.verb), ["list", "images", "catalog"]);
            compare(runner.last.downloading, null);
            compare(lastChanges, 2);
        }

        function test_a_follow_queued_behind_an_apply_leaves_last_alone() {
            let answers = 0;
            compare(runner.apply(context, "vgs", () => answers++), "ok");
            compare(runner.last.applying, "vgs");
            runner.follow();
            compare(lastChanges, 1);
            const result = { state: "applied", shell: "applied", targets: [], theme: "vgs", reason: null };
            finishJob(started(), result);
            compare(answers, 1);
            compare(runner.last.applying, null);
            compare(runner.last.result, result);
            compare(lastChanges, 3);
            finishJob(started(), { state: "unchanged", shell: "unchanged", targets: [], theme: "vgs", reason: null, follow: "current" });
            compare(runner.jobs.length, 0);
            compare(lastChanges, 3);
        }
    }
}
