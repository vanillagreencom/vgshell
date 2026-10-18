import QtQuick
import QtTest
import Quickshell.Io
import "../../shell/plugins/vgs.google-drive" as Drive
import "../../shell/plugins/vgs.google-drive/GoogleDriveLogic.js" as Logic

// The Google Drive service while the runner holds the rename from the
// plugin's previous name: each runner call is a Process stand-in finished
// by hand. A held answer publishes the held sync value with no failure,
// and the service asks for the status again with no outside call. The
// retry timer's interval is shortened so the case waits no 15 seconds.
Item {
    id: root

    property var writes: []

    Component {
        id: serviceComponent
        Drive.Service {}
    }

    TestCase {
        name: "googledrive_service"
        when: windowShown

        property var service: null

        function init() {
            root.writes = [];
            ProcessRegistry.clear();
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
            service.shell = {
                secrets: { revision: 0 },
                tui: { state: {} },
                ipc: { handle: () => {} },
                notify: { send: () => "ok" },
                surfaces: { summon: () => "ok" },
                status: { values: {}, set: (key, value) => { root.writes = root.writes.concat([{ key: key, value: value }]); return "ok"; } }
            };
        }

        function cleanup() {
            service = null;
            ProcessRegistry.clear();
        }

        function running(verb) {
            const found = ProcessRegistry.runningWithVerb(verb);
            return found.length === 1 ? found[0] : null;
        }

        function lastSync() {
            const rows = root.writes.filter(row => row.key === "sync");
            return rows.length === 0 ? undefined : rows[rows.length - 1].value;
        }

        // expected-log: google-drive: status exit=75 google-drive: refused: migration=held reason=old-service-activating -- the service logs the hold once when it begins
        function test_held_rename_is_asked_again() {
            const held = "google-drive: refused: migration=held reason=old-service-activating\n";
            tryVerify(() => running("status") !== null);
            running("status").finish(Logic.RUNNER_HELD, 0, "", held);
            compare(service.heldReason, "old-sync");
            compare(service.problem, "", "a held answer is no failure");
            verify(lastSync() !== undefined && lastSync() !== null, "the sync value says why it waits before any record");
            compare(lastSync().tone, "info");

            // The start asks twice, once for the shell and once for the
            // TUI records it brings; every call still waiting is held too.
            for (let calls = 0; ProcessRegistry.processes.some(p => p.running); calls++) {
                verify(calls < 10, "the runner calls at start end");
                ProcessRegistry.processes.find(p => p.running).finish(Logic.RUNNER_HELD, 0, "", held);
            }
            compare(service.problem, "");

            const timer = Array.from(service.resources).find(item => item.interval === Logic.HELD_RETRY_MS);
            verify(timer !== undefined);
            timer.interval = 20;
            tryVerify(() => running("status") !== null, 2000, "the held status request is asked again");
            running("status").finish(0, 0, "", "");
            compare(service.heldReason, "");
            compare(lastSync(), null, "an answered status clears the held value");
        }
    }
}
