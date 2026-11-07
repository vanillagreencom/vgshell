import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import "../../shell/plugins/vgs.local-sync" as Sync

// The Local Sync service over Process stand-ins finished by hand: one
// direct rsync unit and one Automations unit. A read runs its steps one
// process at a time; the store's new text lists the automation's job; a
// read asked for while a copy check runs waits for it, so each unit keeps
// its own answer; and an event of the exec watch other than an open finds
// the engines again and watches their new files.
Item {
    id: root

    property var published: null

    Component {
        id: serviceComponent
        Sync.Service {}
    }

    TestCase {
        name: "local_sync_service"
        when: windowShown

        property var service: null

        readonly property string units: "notes.service enabled enabled\nvgs-automation-photos.service static -\n"
        readonly property string show: [
            ["Id=notes.service", "LoadState=loaded", "ActiveState=inactive", "Type=oneshot", "Result=success",
                "ExecStart={ path=/usr/bin/rsync ; argv[]=/usr/bin/rsync -a /home/u/notes/ /mnt/notes/ ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }"].join("\n"),
            ["Id=vgs-automation-photos.service", "LoadState=loaded", "ActiveState=inactive", "Type=oneshot", "Result=success",
                "ExecStart={ path=/usr/bin/node ; argv[]=/usr/bin/node /engine run --scheduled photos ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }"].join("\n")
        ].join("\n\n")
        readonly property string store: JSON.stringify({ version: 2, automations: [{ id: "photos", name: "Photos", command: "rsync -a /home/u/Pictures/ /mnt/photos/" }] })

        function init() {
            root.published = null;
            ProcessRegistry.clear();
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
            service.shell = {
                manifest: { id: "vgs.local-sync" },
                requirements: { missing: [] },
                ipc: { handle: () => {} },
                status: { values: {}, isOk: PluginLogic.statusReplyOk, set: (key, value) => { root.published = value; return "ok"; } }
            };
        }

        function cleanup() {
            service = null;
            ProcessRegistry.clear();
        }

        // The one running process whose command starts with WORDS, or null.
        function running(words) {
            const found = ProcessRegistry.processes.filter(p => p.running && words.every((word, i) => p.command[i] === word));
            return found.length === 1 ? found[0] : null;
        }

        function finish(words, out) {
            tryVerify(() => running(words) !== null, 5000, "runs " + words.join(" "));
            running(words).finish(0, 0, out, "");
        }

        function busctlFor(unit) {
            return ProcessRegistry.processes.find(p => p.running && p.command[0] === "busctl" && p.command[p.command.length - 1] === unit) || null;
        }

        function processes(engines) {
            return JSON.stringify({ type: "a(sus)", data: [engines.map((command, i) => ["/app.slice/x.service", 100 + i, command])] });
        }

        // The engines' paths, found once or again as the start asks, until
        // the exec watch runs on them.
        function start() {
            for (let finds = 0; running(["inotifywait"]) === null; finds++) {
                verify(finds < 3, "the start finds the engines at most twice");
                finish(["realpath"], "/usr/bin/rsync\n");
            }
        }

        // One whole read, each copy check answering no engine: the units,
        // their properties, each unit's processes and each job's journal.
        function wholeRead() {
            finish(["systemctl", "--user", "list-unit-files"], units);
            finish(["systemctl", "--user", "show"], show);
            // The follower is a journalctl too, which runs throughout.
            const step = p => p.running && (p.command[0] === "busctl" || (p.command[0] === "journalctl" && p.command[2] === "--no-pager"));
            for (let steps = 0; steps < 8 && !(root.published !== null && root.published.ready && service.pending === null); steps++) {
                tryVerify(() => ProcessRegistry.processes.some(step));
                const next = ProcessRegistry.processes.find(step);
                next.finish(0, 0, next.command[0] === "busctl" ? processes([]) : "", "");
            }
            compare(service.pending, null, "the read ends");
        }

        function listed() {
            return root.published === null ? [] : root.published.jobs.map(job => [job.unit, job.name]);
        }

        // The store's new text, such as a sync job Automations saved after
        // the start, lists that automation's job by its stored name.
        function test_a_store_change_lists_the_automation() {
            start();
            wholeRead();
            tryVerify(() => root.published !== null && root.published.ready);
            compare(JSON.stringify(listed()), JSON.stringify([["notes.service", "Notes"]]), "no store, no automation job");
            service.storeRead(store);
            wholeRead();
            tryVerify(() => listed().length === 2, 5000, "the new store text reads the jobs again");
            compare(JSON.stringify(listed()), JSON.stringify([["notes.service", "Notes"], ["vgs-automation-photos.service", "Photos"]]));
            service.storeRead(null);
            wholeRead();
            tryVerify(() => listed().length === 1, 5000, "a store that went reads the jobs again");
        }

        // A read asked for while a copy check runs waits for it: the
        // check's answers stay with their own units.
        function test_a_read_waits_for_the_copy_check() {
            start();
            wholeRead();
            tryVerify(() => root.published !== null && root.published.ready);
            service.checkCopies("all");
            tryVerify(() => busctlFor("notes.service") !== null);
            service.read();
            compare(running(["systemctl", "--user", "list-unit-files"]), null, "no read starts beside the check");
            busctlFor("notes.service").finish(0, 0, processes(["rsync -a /home/u/notes/ /mnt/notes/"]), "");
            compare(JSON.stringify(root.published.copying), JSON.stringify(["notes.service"]), "the check's answer is its own unit's");
            verify(running(["systemctl", "--user", "list-unit-files"]) !== null, "the read starts once the check ends");
        }

        // A package upgrade replaces an engine's file: the watch's other
        // event finds the engines again and watches the new files, and logs
        // no end of the watch.
        function test_a_replaced_engine_is_watched_again() {
            start();
            const watch = running(["inotifywait"]);
            watch.stdout.read("ATTRIB /usr/bin/rsync");
            compare(watch.running, false, "the old watch stops");
            finish(["realpath"], "/usr/bin/rsync\n");
            tryVerify(() => running(["inotifywait"]) !== null, 5000, "the watch runs again");
            verify(String(running(["inotifywait"]).command).indexOf("open,attrib,delete_self,move_self") !== -1);
        }
    }
}
